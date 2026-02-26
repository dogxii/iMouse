//
//  NewFileAction.swift
//  iMouse
//
//  「新建文件」动作：在当前文件夹中创建一个空白文件。
//  支持多种文件类型模板，自动避免文件名冲突（Untitled.txt → Untitled 2.txt → …）。
//

import AppKit
import UniformTypeIdentifiers

struct NewFileAction: ContextAction {

    // MARK: - 标识

    let id = "action.newFile"

    var displayName: String {
        NSLocalizedString("action.newFile.name", comment: "新建文件")
    }

    var displayDescription: String {
        NSLocalizedString("action.newFile.desc", comment: "在当前文件夹中创建空白文件")
    }

    let sfSymbolName = "doc.badge.plus"

    // MARK: - 可见性

    /// 「新建文件」只在以下情况显示：
    /// - 右键点击文件夹背景（空白处）
    /// - 右键点击桌面
    /// - 右键点击某个文件夹
    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .folderBackground, .desktop, .folders:
            return true
        default:
            return false
        }
    }

    // MARK: - 菜单表示

    /// 生成带子菜单的菜单项，列出所有可用的文件模板。
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        let settings = AppSettings.load()
        let templates = settings.newFileTemplates

        // 如果只有一个模板，直接显示为单个菜单项
        if templates.count <= 1 {
            return .single(
                title: displayName,
                icon: NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil)
            )
        }

        // 多个模板 → 显示为子菜单
        let children = templates.map { template in
            (
                id: template.extension_,
                title: "\(template.displayName) (.\(template.extension_))",
                icon: nil as NSImage?
            )
        }

        return .submenu(
            title: displayName,
            icon: NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil),
            children: children
        )
    }

    // MARK: - 执行

    func perform(context: SelectionContext, submenuId: String?) {
        let settings = AppSettings.load()

        // 确定文件扩展名
        let ext: String
        if let submenuId, !submenuId.isEmpty {
            ext = submenuId
        } else {
            ext = settings.defaultNewFileExtension
        }

        // 确定目标文件夹
        guard let folderURL = resolveTargetFolder(context: context) else {
            showAlert(
                title: NSLocalizedString("action.newFile.error.title", comment: "无法创建文件"),
                message: NSLocalizedString("action.newFile.error.noFolder", comment: "无法确定目标文件夹。")
            )
            return
        }

        // 生成不冲突的文件名
        let baseName = NSLocalizedString("action.newFile.defaultName", comment: "Untitled")
        let fileURL = uniqueFileURL(in: folderURL, baseName: baseName, extension: ext)

        // 创建空文件
        let fm = FileManager.default
        let success = fm.createFile(atPath: fileURL.path(percentEncoded: false), contents: Data(), attributes: nil)

        if success {
            // 在 Finder 中选中并开始重命名新文件
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            showAlert(
                title: NSLocalizedString("action.newFile.error.title", comment: "无法创建文件"),
                message: String(
                    format: NSLocalizedString("action.newFile.error.createFailed", comment: "无法在 %@ 中创建文件。"),
                    folderURL.path(percentEncoded: false)
                )
            )
        }
    }

    // MARK: - 私有方法

    /// 确定新建文件应放在哪个文件夹中。
    private func resolveTargetFolder(context: SelectionContext) -> URL? {
        // 如果选中了一个文件夹 → 在该文件夹内新建
        if let firstFolder = context.folders.first {
            return firstFolder.url
        }
        // 否则使用 Finder 窗口的当前文件夹
        return context.currentFolderURL
    }

    /// 在指定文件夹中生成一个不冲突的文件名。
    ///
    /// 命名规则：
    /// - 第一次: `Untitled.txt`
    /// - 如果已存在: `Untitled 2.txt`、`Untitled 3.txt`、...
    ///
    /// - Parameters:
    ///   - folder: 目标文件夹 URL
    ///   - baseName: 基础文件名（不含扩展名），例如 "Untitled"
    ///   - ext: 文件扩展名，例如 "txt"
    /// - Returns: 一个在该文件夹中不存在的文件 URL
    private func uniqueFileURL(in folder: URL, baseName: String, extension ext: String) -> URL {
        let fm = FileManager.default

        // 先尝试不带编号的文件名
        let firstAttempt = folder.appendingPathComponent("\(baseName).\(ext)")
        if !fm.fileExists(atPath: firstAttempt.path(percentEncoded: false)) {
            return firstAttempt
        }

        // 从 2 开始递增编号
        var counter = 2
        while true {
            let candidate = folder.appendingPathComponent("\(baseName) \(counter).\(ext)")
            if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            counter += 1

            // 安全阀：防止无限循环（理论上不会到这里）
            if counter > 10000 {
                // 使用时间戳作为后备方案
                let timestamp = Int(Date().timeIntervalSince1970)
                return folder.appendingPathComponent("\(baseName)_\(timestamp).\(ext)")
            }
        }
    }

    /// 显示错误提示对话框
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "好"))
            alert.runModal()
        }
    }
}
