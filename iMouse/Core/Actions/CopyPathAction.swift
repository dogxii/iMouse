//
//  CopyPathAction.swift
//  iMouse
//
//  「复制路径」动作：将选中文件/文件夹的绝对 POSIX 路径复制到系统剪贴板。
//  支持多选（多个路径之间的分隔符可在设置中配置）。
//

import AppKit
import UniformTypeIdentifiers

struct CopyPathAction: ContextAction {

    // MARK: - 标识

    let id = "action.copyPath"

    var displayName: String {
        NSLocalizedString("action.copyPath.name", comment: "复制路径")
    }

    var displayDescription: String {
        NSLocalizedString("action.copyPath.desc", comment: "将选中项的绝对路径复制到剪贴板")
    }

    let sfSymbolName = "doc.on.clipboard"

    // MARK: - 可见性

    /// 「复制路径」只要有选中项就显示（文件、文件夹、混合选择均可）。
    /// 在背景/桌面空白处右键时不显示（因为没有具体路径可复制）。
    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .files, .folders, .mixed:
            return true
        case .folderBackground, .desktop:
            // 背景右键时，可以复制当前文件夹的路径
            return context.currentFolderURL != nil
        case .none:
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
        let settings = AppSettings.load()
        let separator = settings.pathSeparator.character

        // 收集要复制的路径
        let paths: [String]

        if context.items.isEmpty {
            // 背景右键 → 复制当前文件夹路径
            if let folderURL = context.currentFolderURL {
                paths = [folderURL.path(percentEncoded: false)]
            } else {
                return
            }
        } else {
            // 有选中项 → 复制所有选中项的绝对路径
            paths = context.items.map { $0.absolutePath }
        }

        // 用配置的分隔符拼接
        let joinedPaths = paths.joined(separator: separator)

        // 写入系统剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(joinedPaths, forType: .string)
    }
}
