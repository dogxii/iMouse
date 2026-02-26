//
//  iMouseApp.swift
//  iMouse
//
//  主应用入口 —— 纯 AppKit 实现。
//
//  ── 核心设计原则 ──
//  1. 不使用任何 SwiftUI Scene（包括 MenuBarExtra、Settings、Window）
//     SwiftUI Scene 会在启动时创建隐藏的 AppKit 窗口并 order front，导致弹窗。
//  2. 使用 NSStatusBar 原生 API 创建菜单栏图标和下拉菜单。
//  3. 设置窗口通过 NSWindow + NSHostingView 按需创建，只在用户点击时才出现。
//  4. URL scheme 通过 NSApplicationDelegate 处理，不使用 .onOpenURL。
//  5. 主 App 不启用沙盒，访问 App Group UserDefaults 不触发 TCC。
//  6. 不使用 AuthorizedFolder / security-scoped bookmark（非沙盒不需要）。
//  7. FinderSync 扩展监控根目录 "/"，覆盖所有场景。
//

import AppKit
import SwiftUI
import ImageIO

// MARK: - App Entry Point

/// 纯 AppKit 应用入口。
/// 不使用 @main struct App: SwiftUI.App，因为 SwiftUI App lifecycle
/// 会自动创建窗口（即使只有 MenuBarExtra 也可能触发隐藏窗口）。
/// 改为经典的 NSApplicationMain 入口。
@main
final class AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 不在 Dock 中显示
        app.run()
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // ── 菜单栏 ──
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!

    // ── 设置窗口（懒创建，只在用户点击时才实例化） ──
    private var settingsWindow: NSWindow?
    private var settingsHostingView: NSHostingView<AnyView>?

    // MARK: - 应用启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[iMouse] 应用启动完成 (纯 AppKit 模式)")

        // 确保不在 Dock 中显示
        NSApplication.shared.setActivationPolicy(.accessory)

        // 禁用 macOS 窗口恢复机制 —— 防止上次打开的设置窗口在下次启动时自动恢复弹出
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // 禁用自动窗口标签页
        NSWindow.allowsAutomaticWindowTabbing = false

        // 清除已保存的窗口恢复状态，防止历史残留导致弹窗
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame iMouse Settings")
            UserDefaults.standard.removePersistentDomain(forName: "\(bundleId).savedState")
        }

        // 创建菜单栏
        setupStatusBar()

        NSLog("[iMouse] 菜单栏已创建")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - URL Scheme 处理

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        NSLog("[iMouse URL] 收到 URL: %@", url.absoluteString)

        guard url.scheme == "imouse" else {
            NSLog("[iMouse URL] 未知 scheme: %@", url.scheme ?? "nil")
            return
        }

        switch url.host {
        case "airdrop":
            handleAirDropURL(url)
        case "terminal":
            handleTerminalURL(url)
        case "convert-webp":
            handleConvertWebPURL(url)
        case "settings":
            DispatchQueue.main.async { [weak self] in
                self?.openSettingsWindow()
            }
        default:
            NSLog("[iMouse URL] 未知 host: %@", url.host ?? "nil")
        }
    }

    // MARK: - 菜单栏设置

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "iMouse")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true // 自动适配暗色/亮色模式
        }

        statusMenu = NSMenu()
        rebuildStatusMenu()
        statusItem.menu = statusMenu
    }

    /// 重建状态菜单（每次打开都刷新，确保状态最新）
    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.delegate = self

        // 打开设置
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menubar.openSettings", comment: "打开设置…"),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        statusMenu.addItem(settingsItem)

        // Finder 扩展设置
        let extensionItem = NSMenuItem(
            title: NSLocalizedString("menubar.extensionSettings", comment: "Finder 扩展设置…"),
            action: #selector(openExtensionSettingsAction),
            keyEquivalent: ""
        )
        extensionItem.target = self
        extensionItem.image = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        statusMenu.addItem(extensionItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: NSLocalizedString("menubar.quit", comment: "退出 iMouse"),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        statusMenu.addItem(quitItem)
    }

    // MARK: - 菜单动作

    @objc private func openSettingsAction() {
        openSettingsWindow()
    }

    @objc private func openExtensionSettingsAction() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 设置窗口管理

    /// 打开设置窗口。
    /// 窗口在首次调用时创建，之后复用同一个窗口实例。
    /// 如果窗口已可见，只是将其提到前台。
    func openSettingsWindow() {
        // 如果窗口已存在且可见，直接提到前台
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // 如果窗口已存在但被关闭了，重新显示
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // 首次创建设置窗口
        let settingsView = SettingsView()
            .environmentObject(SettingsManager.shared)

        let hostingView = NSHostingView(rootView: AnyView(settingsView))
        hostingView.frame = NSRect(x: 0, y: 0, width: 580, height: 500)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("settings.window.title", comment: "iMouse Settings")
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false // 关闭时不释放，下次可以重新显示
        window.isRestorable = false         // 禁止 macOS 在下次启动时自动恢复此窗口
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)

        self.settingsWindow = window
        self.settingsHostingView = hostingView

        NSLog("[iMouse] 设置窗口已创建并显示")
    }

    // MARK: - Terminal URL 处理

    /// 从 URL 中提取目录路径和标签页标志，调用 TerminalLauncher 启动终端。
    /// URL 格式: imouse://terminal?dir=<percent-encoded-path>&tab=<0|1>
    ///
    /// 这个方法由 FinderSync 扩展通过 URL scheme 委托调用。
    /// 扩展运行在沙盒中，无法可靠地直接启动终端应用，
    /// 所以通过 URL scheme 将请求转发到非沙盒的主 App 进程。
    private func handleTerminalURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dirParam = components.queryItems?.first(where: { $0.name == "dir" })?.value else {
            NSLog("[iMouse Terminal URL] 缺少 dir 参数")
            return
        }

        let asTab: Bool
        if let tabParam = components.queryItems?.first(where: { $0.name == "tab" })?.value {
            asTab = (tabParam == "1")
        } else {
            asTab = false
        }

        let dirURL = URL(fileURLWithPath: dirParam, isDirectory: true)

        // 验证目录存在
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirParam, isDirectory: &isDir), isDir.boolValue else {
            NSLog("[iMouse Terminal URL] 目录不存在或不是文件夹: %@", dirParam)
            // 如果路径是文件，使用其父目录
            let parentDir = dirURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir), isDir.boolValue {
                NSLog("[iMouse Terminal URL] 使用父目录: %@", parentDir.path)
                TerminalLauncher.launch(workingDirectory: parentDir, asTab: asTab)
            }
            return
        }

        NSLog("[iMouse Terminal URL] 在主 App 中启动终端, dir: %@, asTab: %d", dirParam, asTab ? 1 : 0)
        TerminalLauncher.launch(workingDirectory: dirURL, asTab: asTab)
    }

    // MARK: - WebP 转换 URL 处理

    /// 从 URL 中提取图片路径和质量参数，调用 cwebp 执行 WebP 转换。
    /// URL 格式: imouse://convert-webp?files=<newline-separated paths>&quality=<0-100>
    ///
    /// FinderSync 扩展在沙盒中无法访问 /opt/homebrew/bin/cwebp，
    /// 通过此 URL scheme 委托给非沙盒的主 App 执行。
    private func handleConvertWebPURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value else {
            NSLog("[iMouse WebP URL] 缺少 files 参数")
            return
        }

        let qualityInt = Int(components.queryItems?.first(where: { $0.name == "quality" })?.value ?? "85") ?? 85
        let quality = Double(qualityInt) / 100.0

        let paths = filesParam.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            NSLog("[iMouse WebP URL] 没有可转换的文件")
            return
        }

        NSLog("[iMouse WebP URL] 收到 WebP 转换请求：%d 个文件，quality: %d", paths.count, qualityInt)

        DispatchQueue.global(qos: .userInitiated).async {
            // 查找 cwebp
            guard let cwebpPath = self.findCwebp() else {
                NSLog("[iMouse WebP URL] 未找到 cwebp，提示用户安装")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("action.convert.error.title", comment: "转换失败")
                    alert.informativeText = NSLocalizedString(
                        "action.convert.error.webpNotSupported",
                        comment: "macOS does not natively support writing WebP format.\n\nTo enable WebP conversion, please install the WebP tools via Homebrew:\n\n  brew install webp\n\nThen try again."
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
                    alert.runModal()
                }
                return
            }

            NSLog("[iMouse WebP URL] 使用 cwebp: %@", cwebpPath)

            var failedFiles: [String] = []

            for sourcePath in paths {
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let sourceExt = sourceURL.pathExtension.lowercased()

                // 确定输出路径（避免同名冲突）
                let destURL = self.uniqueWebPOutputURL(sourceURL: sourceURL, baseName: baseName)

                // cwebp 支持的输入格式: PNG, JPEG, TIFF, WebP
                // 其他格式（HEIC, BMP, GIF 等）先转换为临时 PNG
                let cwebpNativeInputs = ["png", "jpg", "jpeg", "tif", "tiff", "webp"]
                var inputURL = sourceURL
                var tempFileURL: URL? = nil

                if !cwebpNativeInputs.contains(sourceExt) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempPNG = tempDir.appendingPathComponent("imouse_webp_\(UUID().uuidString.prefix(8)).png")

                    if let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                       let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                       let dest = CGImageDestinationCreateWithURL(tempPNG as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, cgImage, nil)
                        if CGImageDestinationFinalize(dest) {
                            inputURL = tempPNG
                            tempFileURL = tempPNG
                        }
                    }

                    if inputURL == sourceURL {
                        // 临时 PNG 创建失败
                        NSLog("[iMouse WebP URL] 无法创建临时 PNG: %@", sourcePath)
                        failedFiles.append(sourceURL.lastPathComponent)
                        continue
                    }
                }

                // 调用 cwebp
                let success = self.runCwebp(
                    cwebpPath: cwebpPath,
                    inputPath: inputURL.path(percentEncoded: false),
                    outputPath: destURL.path(percentEncoded: false),
                    quality: qualityInt
                )

                // 清理临时文件
                if let tmp = tempFileURL {
                    try? FileManager.default.removeItem(at: tmp)
                }

                if success {
                    NSLog("[iMouse WebP URL] ✅ 转换成功: %@", destURL.lastPathComponent)
                } else {
                    NSLog("[iMouse WebP URL] ❌ 转换失败: %@", sourceURL.lastPathComponent)
                    failedFiles.append(sourceURL.lastPathComponent)
                    // 清理可能产生的损坏输出文件
                    if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
                        try? FileManager.default.removeItem(at: destURL)
                    }
                }
            }

            // 有失败时在主线程弹窗
            if !failedFiles.isEmpty {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("action.convert.error.title", comment: "转换失败")
                    alert.informativeText = String(
                        format: NSLocalizedString("action.convert.error.someFailed", comment: "以下文件转换失败:\n%@"),
                        failedFiles.joined(separator: "\n")
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
                    alert.runModal()
                }
            }
        }
    }

    /// 在常见路径中查找 cwebp 可执行文件
    private func findCwebp() -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/cwebp",   // Apple Silicon Homebrew
            "/usr/local/bin/cwebp",      // Intel Homebrew
            "/opt/local/bin/cwebp",      // MacPorts
            "/usr/bin/cwebp",
        ]
        let fm = FileManager.default
        for path in searchPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 通过 zsh 查找（处理用户自定义 PATH）
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which cwebp"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let output, !output.isEmpty, fm.isExecutableFile(atPath: output) {
                    return output
                }
            }
        } catch {
            NSLog("[iMouse WebP URL] which cwebp failed: %@", error.localizedDescription)
        }
        return nil
    }

    /// 调用 cwebp 将图片转换为 WebP
    private func runCwebp(cwebpPath: String, inputPath: String, outputPath: String, quality: Int) -> Bool {
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cwebpPath)
        process.arguments = ["-q", "\(quality)", inputPath, "-o", outputPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                NSLog("[iMouse WebP URL] cwebp 失败 (exit %d): %@", process.terminationStatus, errStr)
                return false
            }
            return true
        } catch {
            NSLog("[iMouse WebP URL] cwebp 启动失败: %@", error.localizedDescription)
            return false
        }
    }

    /// 生成不冲突的 WebP 输出路径
    private func uniqueWebPOutputURL(sourceURL: URL, baseName: String) -> URL {
        let parentDir = sourceURL.deletingLastPathComponent()
        let fm = FileManager.default

        let first = parentDir.appendingPathComponent("\(baseName).webp")
        if !fm.fileExists(atPath: first.path(percentEncoded: false)) { return first }

        let converted = parentDir.appendingPathComponent("\(baseName)_converted.webp")
        if !fm.fileExists(atPath: converted.path(percentEncoded: false)) { return converted }

        var counter = 2
        while counter <= 10000 {
            let candidate = parentDir.appendingPathComponent("\(baseName)_converted \(counter).webp")
            if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
            counter += 1
        }
        return parentDir.appendingPathComponent("\(baseName)_\(Int(Date().timeIntervalSince1970)).webp")
    }

    // MARK: - AirDrop URL 处理

    /// 从 URL 中提取文件路径，调用 NSSharingService 执行 AirDrop。
    /// URL 格式: imouse://airdrop?files=<percent-encoded newline-separated paths>
    private func handleAirDropURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value else {
            NSLog("[iMouse AirDrop URL] 缺少 files 参数")
            return
        }

        let paths = filesParam.components(separatedBy: "\n").filter { !$0.isEmpty }
        let fm = FileManager.default

        var fileURLs: [URL] = []
        var hasFolder = false

        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    hasFolder = true
                    NSLog("[iMouse AirDrop URL] 跳过文件夹: %@", path)
                } else {
                    fileURLs.append(fileURL)
                }
            } else {
                NSLog("[iMouse AirDrop URL] 文件不存在: %@", path)
            }
        }

        if fileURLs.isEmpty && hasFolder {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("action.airDrop.error.title", comment: "AirDrop")
                alert.informativeText = NSLocalizedString(
                    "action.airDrop.error.foldersNotSupported",
                    comment: "AirDrop cannot share folders directly."
                )
                alert.alertStyle = .informational
                alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
                alert.runModal()
            }
            return
        }

        guard !fileURLs.isEmpty else {
            NSLog("[iMouse AirDrop URL] 没有可分享的文件")
            return
        }

        DispatchQueue.main.async {
            guard let airDropService = NSSharingService(named: .sendViaAirDrop) else {
                NSLog("[iMouse AirDrop URL] NSSharingService(named: .sendViaAirDrop) returned nil")
                return
            }
            NSLog("[iMouse AirDrop URL] 通过 AirDrop 分享 %d 个文件", fileURLs.count)
            airDropService.perform(withItems: fileURLs as [Any])
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// 每次菜单即将打开时刷新内容
    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusMenu {
            rebuildStatusMenu()
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时不做特殊处理，窗口实例保留以便重用
        NSLog("[iMouse] 设置窗口已关闭")
    }
}
