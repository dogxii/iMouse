//
//  CopyNameAction.swift
//  iMouse
//
//  「复制名称」动作：将选中文件/文件夹的名称（不含路径）复制到系统剪贴板。
//  可在设置中配置是否包含扩展名。
//  支持多选（多个名称之间用换行符分隔）。
//

import AppKit
import UniformTypeIdentifiers

struct CopyNameAction: ContextAction {

    // MARK: - 标识

    let id = "action.copyName"

    var displayName: String {
        NSLocalizedString("action.copyName.name", comment: "复制名称")
    }

    var displayDescription: String {
        NSLocalizedString("action.copyName.desc", comment: "将选中项的文件/文件夹名称复制到剪贴板")
    }

    let sfSymbolName = "textformat"

    // MARK: - 可见性

    /// 「复制名称」只要有选中项就显示（文件、文件夹、混合选择均可）。
    /// 在背景/桌面空白处右键时也可以显示（复制当前文件夹名称）。
    func isVisible(for context: SelectionContext) -> Bool {
        switch context.kind {
        case .files, .folders, .mixed:
            return true
        case .folderBackground, .desktop:
            // 背景右键时，可以复制当前文件夹的名称
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

        // 收集要复制的名称
        let names: [String]

        if context.items.isEmpty {
            // 背景右键 → 复制当前文件夹名称
            if let folderURL = context.currentFolderURL {
                let folderName = folderURL.lastPathComponent
                names = [folderName]
            } else {
                return
            }
        } else {
            // 有选中项 → 根据设置决定是否包含扩展名
            names = context.items.map { item in
                nameForItem(item, mode: settings.copyNameMode)
            }
        }

        // 用配置的分隔符拼接
        let joinedNames = names.joined(separator: separator)

        // 写入系统剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(joinedNames, forType: .string)
    }

    // MARK: - 私有方法

    /// 根据设置的模式返回文件项的名称。
    ///
    /// - Parameters:
    ///   - item: 选中的文件项
    ///   - mode: 复制名称模式（包含/不含扩展名）
    /// - Returns: 文件/文件夹名称字符串
    private func nameForItem(_ item: FileItem, mode: CopyNameMode) -> String {
        switch mode {
        case .withExtension:
            // 返回完整名称，例如 "photo.png"、"Documents"
            return item.name
        case .withoutExtension:
            // 返回不含扩展名的名称，例如 "photo"、"Documents"
            // 对于文件夹或没有扩展名的文件，nameWithoutExtension 和 name 相同
            return item.nameWithoutExtension
        }
    }
}
