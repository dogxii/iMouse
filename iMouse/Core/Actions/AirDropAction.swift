//
//  AirDropAction.swift
//  iMouse
//
//  「AirDrop」动作：通过 AirDrop 发送选中的文件。
//
//  ── 关键设计决策 ──
//  FinderSync 扩展运行在沙盒化的 XPC 插件进程中，
//  NSSharingService.perform(withItems:) 在此环境下不受支持
//  （系统日志会输出 "Performing sharing services not supported. Running in plugin."）。
//
//  解决方案：
//  - 扩展通过 URL scheme (imouse://airdrop?files=...) 将文件路径传递给主 App
//  - 主 App (iMouseApp.swift AppDelegate) 接收 URL 并在自己的进程中执行 AirDrop
//  - 这种方式不需要 DistributedNotificationCenter（会触发 TCC 弹窗），
//    也不需要 NSSharingService 在扩展中运行
//
//  参考：RClick 项目通过 DistributedNotificationCenter 将操作委托给主 App，
//  但 DistributedNotification 在沙盒中会触发 TCC 弹窗，所以我们改用 URL scheme。
//

import AppKit

struct AirDropAction: ContextAction {

    // MARK: - 标识

    let id = "action.airDrop"

    var displayName: String {
        NSLocalizedString("action.airDrop.name", comment: "AirDrop")
    }

    var displayDescription: String {
        NSLocalizedString("action.airDrop.desc", comment: "通过 AirDrop 发送选中的文件或文件夹")
    }

    let sfSymbolName = "airplayaudio"

    // MARK: - 可见性

    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .files, .folders, .mixed:
            return true
        case .folderBackground, .desktop, .none:
            return false
        }
    }

    // MARK: - 菜单表示

    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        .single(
            title: displayName,
            icon: NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil)
        )
    }

    // MARK: - 执行

    func perform(context: SelectionContext, submenuId: String?) {
        let urls = context.urls
        guard !urls.isEmpty else { return }

        // 将文件路径编码到 URL scheme 中，委托给主 App 执行 AirDrop
        // 主 App 的 AppDelegate.handleURLEvent 会接收并处理
        delegateToMainApp(urls: urls)
    }

    // MARK: - 委托给主 App

    /// 通过 imouse://airdrop URL scheme 将文件路径传递给主 App。
    ///
    /// URL 格式: imouse://airdrop?files=<percent-encoded newline-separated paths>
    /// 使用换行符分隔路径（避免路径中包含逗号的问题）。
    private func delegateToMainApp(urls: [URL]) {
        // 将所有路径用换行符连接
        let paths = urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n")

        // 构建 URL: imouse://airdrop?files=<encoded-paths>
        var components = URLComponents()
        components.scheme = "imouse"
        components.host = "airdrop"
        components.queryItems = [
            URLQueryItem(name: "files", value: paths)
        ]

        guard let url = components.url else {
            NSLog("[iMouse AirDrop] 无法构建 imouse://airdrop URL")
            return
        }

        NSLog("[iMouse AirDrop] 委托给主 App 执行 AirDrop，文件数: %d", urls.count)

        // 使用 NSWorkspace 打开 URL scheme，系统会将其路由到主 App
        NSWorkspace.shared.open(url)
    }
}
