//
//  NewGhosttyWindowAction.swift
//  iMouse
//
//  终端动作：在选中文件夹（或文件所在目录）打开终端。
//  拆分为两个独立的顶层动作：
//  - NewTerminalWindowAction: 新建终端窗口
//  - NewTerminalTabAction: 新建终端标签页
//
//  支持多种终端应用：Ghostty, Terminal.app, iTerm2, Warp, Kitty, Alacritty 等。
//
//  ── 关键设计决策 ──
//  FinderSync 扩展运行在沙盒化的 XPC 插件进程中，
//  NSWorkspace.shared.open(_:withApplicationAt:configuration:) 在沙盒中
//  无法可靠地传递 arguments / 工作目录给终端应用。
//
//  解决方案（参考 RClick 的委托模式）：
//  - 扩展通过 URL scheme (imouse://terminal?dir=<path>&tab=0) 将目录路径传递给主 App
//  - 主 App (iMouseApp.swift AppDelegate) 接收 URL 并在非沙盒进程中执行终端启动
//  - 主 App 使用 NSWorkspace.shared.open 通过 Launch Services 打开终端应用
//  - 这种方式不需要 Automation 权限，不触发 TCC 弹窗
//
//  RClick 使用 DistributedNotificationCenter 在扩展和主 App 之间通信，
//  但 DistributedNotification 在沙盒中可能触发 TCC。
//  我们改用 URL scheme（与 AirDrop 动作一致的模式）。
//

import AppKit
import UniformTypeIdentifiers

// MARK: - 共享终端启动逻辑

/// 终端启动器：封装所有终端应用的启动逻辑。
///
/// 主要使用 NSWorkspace.shared.open 通过 Launch Services 打开终端应用，
/// 参考 RClick 项目的实现方式。
///
/// ⚠️ 重要：此类的方法只应在主 App 进程中调用（非沙盒），
/// 不应在 FinderSync 扩展进程中直接调用。
/// FinderSync 扩展应通过 URL scheme 委托给主 App。
enum TerminalLauncher {

    // MARK: - 主入口

    /// 在指定目录启动终端（窗口或标签页）。
    ///
    /// ⚠️ 此方法只应在主 App 进程中调用。
    /// FinderSync 扩展应使用 `delegateToMainApp(workingDirectory:asTab:)` 代替。
    static func launch(workingDirectory: URL, asTab: Bool) {
        let settings = AppSettings.load()
        let resolvedURL = workingDirectory.standardizedFileURL.resolvingSymlinksInPath()

        NSLog("[iMouse TerminalLauncher] Launching terminal at directory: %@", resolvedURL.path(percentEncoded: false))
        NSLog("[iMouse TerminalLauncher] Terminal app: %@, asTab: %d", settings.terminalApp.displayName, asTab ? 1 : 0)

        switch settings.terminalApp {
        case .ghostty:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .ghostty, asTab: asTab)
        case .terminal:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .terminal, asTab: asTab)
        case .iterm2:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .iterm2, asTab: asTab)
        case .warp:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .warp, asTab: asTab)
        case .kitty:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .kitty, asTab: asTab)
        case .alacritty:
            launchViaWorkspace(dirURL: resolvedURL, terminalApp: .alacritty, asTab: asTab)
        case .custom:
            launchCustom(dirURL: resolvedURL, asTab: asTab, settings: settings)
        }
    }

    // MARK: - 委托给主 App（供 FinderSync 扩展使用）

    /// 通过 imouse://terminal URL scheme 将终端打开请求委托给主 App。
    ///
    /// FinderSync 扩展运行在沙盒中，无法可靠地直接启动终端应用。
    /// 此方法通过 URL scheme 将请求转发给非沙盒的主 App 进程，
    /// 由主 App 调用 `launch(workingDirectory:asTab:)` 执行实际操作。
    ///
    /// URL 格式: imouse://terminal?dir=<percent-encoded-path>&tab=<0|1>
    ///
    /// - Parameters:
    ///   - workingDirectory: 要在终端中打开的目录 URL
    ///   - asTab: 是否作为新标签页打开（true = 标签页，false = 新窗口）
    static func delegateToMainApp(workingDirectory: URL, asTab: Bool) {
        let dirPath = workingDirectory.path(percentEncoded: false)

        var components = URLComponents()
        components.scheme = "imouse"
        components.host = "terminal"
        components.queryItems = [
            URLQueryItem(name: "dir", value: dirPath),
            URLQueryItem(name: "tab", value: asTab ? "1" : "0")
        ]

        guard let url = components.url else {
            NSLog("[iMouse Terminal] 无法构建 imouse://terminal URL, dir: %@", dirPath)
            return
        }

        NSLog("[iMouse Terminal] 委托给主 App 打开终端，目录: %@, asTab: %d", dirPath, asTab ? 1 : 0)

        // 使用 NSWorkspace 打开 URL scheme，系统会将其路由到主 App
        NSWorkspace.shared.open(url)
    }

    // MARK: - NSWorkspace 方式（主要方式，参考 RClick）

    /// 使用 NSWorkspace.shared.open 打开终端应用。
    ///
    /// 这是 RClick 项目使用的方式：将目录 URL 作为「文档」传递给终端应用，
    /// 终端应用会自动在该目录下打开新窗口。
    ///
    /// 工作原理：
    /// - `NSWorkspace.shared.open([dirURL], withApplicationAt: appURL, configuration:)`
    ///   通过 Launch Services 告诉系统「用这个应用打开这个目录」
    /// - 终端应用（Ghostty、iTerm2、Terminal.app 等）收到目录后，
    ///   会在该目录下打开新的终端窗口
    /// - 这个 API 不需要 Automation 权限，不受沙盒限制
    private static func launchViaWorkspace(dirURL: URL, terminalApp: TerminalApp, asTab: Bool) {
        let dirPath = dirURL.path(percentEncoded: false)

        // 1. 尝试通过 bundle identifier 查找应用 URL
        guard let bundleId = terminalApp.bundleIdentifier else {
            NSLog("[iMouse TerminalLauncher] No bundle identifier for %@, falling back to Process", terminalApp.displayName)
            launchViaProcess(dirPath: dirPath, terminalApp: terminalApp, asTab: asTab)
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("[iMouse TerminalLauncher] App not found for bundle ID %@, falling back to Process", bundleId)
            launchViaProcess(dirPath: dirPath, terminalApp: terminalApp, asTab: asTab)
            return
        }

        NSLog("[iMouse TerminalLauncher] Using NSWorkspace.open for %@ at %@", terminalApp.displayName, appURL.path(percentEncoded: false))

        // 2. 配置 NSWorkspace.OpenConfiguration
        let config = NSWorkspace.OpenConfiguration()
        config.promptsUserIfNeeded = false
        config.activates = true

        // 对于支持 CLI 参数的终端，可以通过 arguments 传递工作目录
        // 但 NSWorkspace.open([dirURL], withApplicationAt:) 方式更通用可靠
        switch terminalApp {
        case .ghostty:
            // Ghostty 支持 --working-directory 参数
            // 但直接用目录 URL 打开也能正常工作
            config.arguments = ["--working-directory=\(dirPath)"]
        case .kitty:
            // Kitty 支持 -d 参数指定工作目录
            config.arguments = ["-d", dirPath]
        case .alacritty:
            // Alacritty 支持 --working-directory 参数
            config.arguments = ["--working-directory", dirPath]
        default:
            break
        }

        // 3. 使用 NSWorkspace.shared.open 打开（RClick 的核心方式）
        //    将目录 URL 作为「文档」传递给终端应用
        NSWorkspace.shared.open(
            [dirURL],
            withApplicationAt: appURL,
            configuration: config
        ) { runningApp, error in
            if let error = error {
                NSLog("[iMouse TerminalLauncher] NSWorkspace.open failed for %@: %@", terminalApp.displayName, error.localizedDescription)
                // NSWorkspace 失败时，降级到 Process 方式
                self.launchViaProcess(dirPath: dirPath, terminalApp: terminalApp, asTab: asTab)
            } else if let app = runningApp {
                NSLog("[iMouse TerminalLauncher] ✅ Successfully opened %@ (pid: %d)", app.localizedName ?? terminalApp.displayName, app.processIdentifier)
            }
        }
    }

    // MARK: - Process 方式（降级方案）

    /// 使用 Process (NSTask) + /usr/bin/open 命令打开终端。
    /// 这是 NSWorkspace.open 失败时的降级方案。
    private static func launchViaProcess(dirPath: String, terminalApp: TerminalApp, asTab: Bool) {
        NSLog("[iMouse TerminalLauncher] Falling back to Process for %@", terminalApp.displayName)

        switch terminalApp {
        case .ghostty:
            // open -n -a Ghostty --args --working-directory=<path>
            runProcessAsync(
                arguments: ["-n", "-a", "Ghostty", "--args", "--working-directory=\(dirPath)"],
                errorContext: "Ghostty (Process fallback)",
                fallback: {
                    runProcess(arguments: ["-a", "Ghostty"], errorContext: "Ghostty fallback bare")
                }
            )
        case .terminal:
            // Terminal.app 原生支持: open -a Terminal <folder>
            runProcessAsync(
                arguments: ["-a", "Terminal", dirPath],
                errorContext: "Terminal.app (Process fallback)"
            )
        case .iterm2:
            // iTerm2: open -a iTerm <folder>
            // iTerm2 支持将文件夹路径作为参数直接打开
            runProcessAsync(
                arguments: ["-a", "iTerm", dirPath],
                errorContext: "iTerm2 (Process fallback)",
                fallback: {
                    runProcess(arguments: ["-a", "iTerm"], errorContext: "iTerm2 fallback bare")
                }
            )
        case .warp:
            runProcessAsync(
                arguments: ["-a", "Warp", dirPath],
                errorContext: "Warp (Process fallback)"
            )
        case .kitty:
            runProcessAsync(
                arguments: ["-n", "-a", "kitty", "--args", "-d", dirPath],
                errorContext: "Kitty (Process fallback)",
                fallback: {
                    runProcess(arguments: ["-a", "kitty"], errorContext: "Kitty fallback bare")
                }
            )
        case .alacritty:
            runProcessAsync(
                arguments: ["-n", "-a", "Alacritty", "--args", "--working-directory", dirPath],
                errorContext: "Alacritty (Process fallback)",
                fallback: {
                    runProcess(arguments: ["-a", "Alacritty"], errorContext: "Alacritty fallback bare")
                }
            )
        case .custom:
            // custom 应通过 launchCustom 处理，不会走到这里
            break
        }
    }

    // MARK: - 自定义终端

    /// 自定义终端启动策略：
    ///
    /// 如果路径是 .app bundle：优先使用 NSWorkspace.open 方式打开。
    /// 如果路径是可执行文件：使用 Process 在目标目录运行该可执行文件。
    private static func launchCustom(dirURL: URL, asTab: Bool, settings: AppSettings) {
        let customPath = settings.terminalCustomPath
        let dirPath = dirURL.path(percentEncoded: false)

        guard !customPath.isEmpty else {
            DispatchQueue.main.async {
                showAlert(
                    title: NSLocalizedString("action.terminal.error.title", comment: "Cannot Open Terminal"),
                    message: NSLocalizedString("action.terminal.error.noCustomPath", comment: "No custom terminal path configured.")
                )
            }
            return
        }

        if customPath.hasSuffix(".app") {
            // .app bundle: 优先使用 NSWorkspace.open（参考 RClick）
            let appURL = URL(fileURLWithPath: customPath)

            NSLog("[iMouse TerminalLauncher] Custom .app: using NSWorkspace.open with %@", customPath)

            let config = NSWorkspace.OpenConfiguration()
            config.promptsUserIfNeeded = false
            config.activates = true

            NSWorkspace.shared.open(
                [dirURL],
                withApplicationAt: appURL,
                configuration: config
            ) { runningApp, error in
                if let error = error {
                    NSLog("[iMouse TerminalLauncher] NSWorkspace.open failed for custom app %@: %@", customPath, error.localizedDescription)
                    // 降级：使用 Process + open 命令
                    self.runProcessAsync(
                        arguments: ["-a", customPath, dirPath],
                        errorContext: "Custom terminal (Process fallback)",
                        fallback: {
                            self.runProcess(arguments: ["-a", customPath], errorContext: "Custom terminal bare fallback")
                        }
                    )
                } else if let app = runningApp {
                    NSLog("[iMouse TerminalLauncher] ✅ Custom app opened: %@ (pid: %d)", app.localizedName ?? customPath, app.processIdentifier)
                }
            }
        } else {
            // 可执行文件路径：使用 Process 在目标目录运行
            NSLog("[iMouse TerminalLauncher] Custom executable: %@ in %@", customPath, dirPath)
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: customPath)
                process.currentDirectoryURL = dirURL
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    NSLog("[iMouse TerminalLauncher] ✅ Custom executable launched successfully.")
                } catch {
                    NSLog("[iMouse TerminalLauncher] Custom executable failed: %@", error.localizedDescription)
                    DispatchQueue.main.async {
                        showAlert(
                            title: NSLocalizedString("action.terminal.error.title", comment: "Cannot Open Terminal"),
                            message: String(
                                format: NSLocalizedString("action.terminal.error.notInstalled", comment: "%@ was not found."),
                                customPath
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Process (NSTask) 辅助方法

    /// 使用 Process (NSTask) 执行 /usr/bin/open 命令。
    /// 这是 NSWorkspace.open 的降级方案。
    @discardableResult
    private static func runProcess(
        launchPath: String = "/usr/bin/open",
        arguments: [String],
        errorContext: String
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        let fullCommand = "\(launchPath) \(arguments.joined(separator: " "))"
        NSLog("[iMouse] Running process (%@): %@", errorContext, fullCommand)

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            if status != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                NSLog("[iMouse] Process failed (%@): exit code %d, stderr: %@", errorContext, status, errorMessage)
                return false
            } else {
                NSLog("[iMouse] Process (%@) executed successfully.", errorContext)
                return true
            }
        } catch {
            NSLog("[iMouse] Process launch failed (%@): %@", errorContext, error.localizedDescription)
            return false
        }
    }

    /// 在后台线程执行 Process，避免阻塞 Finder 主线程
    private static func runProcessAsync(
        launchPath: String = "/usr/bin/open",
        arguments: [String],
        errorContext: String,
        fallback: (() -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = runProcess(launchPath: launchPath, arguments: arguments, errorContext: errorContext)
            if !success, let fallback = fallback {
                NSLog("[iMouse] Trying fallback for %@", errorContext)
                fallback()
            }
        }
    }

    // MARK: - 显示错误弹窗

    /// 显示错误弹窗
    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
        alert.runModal()
    }
}


// MARK: - NewTerminalWindowAction（新建终端窗口）

struct NewTerminalWindowAction: ContextAction {

    let id = "action.terminalWindow"

    var displayName: String {
        let settings = AppSettings.load()
        return String(
            format: NSLocalizedString("action.terminal.newWindow", comment: "New %@ Window Here"),
            settings.terminalApp.displayName
        )
    }

    var displayDescription: String {
        NSLocalizedString("action.terminal.windowDesc", comment: "Open a new terminal window at the selected location")
    }

    let sfSymbolName = "terminal"

    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .files, .folders, .mixed, .folderBackground, .desktop:
            return true
        case .none:
            return false
        }
    }

    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        let settings = AppSettings.load()
        let title = String(
            format: NSLocalizedString("action.terminal.newWindow", comment: "New %@ Window Here"),
            settings.terminalApp.displayName
        )
        return .single(
            title: title,
            icon: NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        )
    }

    func perform(context: SelectionContext, submenuId: String?) {
        guard let workingDir = context.effectiveDirectory else {
            NSLog("[iMouse Terminal] 无法确定工作目录，context.kind: %@", String(describing: context.kind))
            return
        }

        NSLog("[iMouse Terminal] NewTerminalWindowAction: 委托给主 App, dir: %@", workingDir.path(percentEncoded: false))

        // 通过 URL scheme 委托给主 App 执行（FinderSync 扩展在沙盒中无法直接启动终端）
        TerminalLauncher.delegateToMainApp(workingDirectory: workingDir, asTab: false)
    }
}


// MARK: - NewTerminalTabAction（新建终端标签页）

struct NewTerminalTabAction: ContextAction {

    let id = "action.terminalTab"

    var displayName: String {
        let settings = AppSettings.load()
        return String(
            format: NSLocalizedString("action.terminal.newTab", comment: "New %@ Tab Here"),
            settings.terminalApp.displayName
        )
    }

    var displayDescription: String {
        NSLocalizedString("action.terminal.tabDesc", comment: "Open a new terminal tab at the selected location")
    }

    let sfSymbolName = "terminal"

    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .files, .folders, .mixed, .folderBackground, .desktop:
            return true
        case .none:
            return false
        }
    }

    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        let settings = AppSettings.load()
        let title = String(
            format: NSLocalizedString("action.terminal.newTab", comment: "New %@ Tab Here"),
            settings.terminalApp.displayName
        )
        return .single(
            title: title,
            icon: NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
        )
    }

    func perform(context: SelectionContext, submenuId: String?) {
        guard let workingDir = context.effectiveDirectory else {
            NSLog("[iMouse Terminal] 无法确定工作目录，context.kind: %@", String(describing: context.kind))
            return
        }

        NSLog("[iMouse Terminal] NewTerminalTabAction: 委托给主 App, dir: %@", workingDir.path(percentEncoded: false))

        // 通过 URL scheme 委托给主 App 执行（FinderSync 扩展在沙盒中无法直接启动终端）
        TerminalLauncher.delegateToMainApp(workingDirectory: workingDir, asTab: true)
    }
}
