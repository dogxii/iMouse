//
//  ContextAction.swift
//  iMouse – Shared
//
//  ContextAction 是所有右键菜单动作的基础协议。
//  要添加新动作，只需创建一个遵循此协议的新类型，然后在 ActionRegistry 中注册即可。
//  这就是整个架构的「扩展点」。
//

import AppKit
import UniformTypeIdentifiers

// MARK: - MenuItemRepresentation（菜单项表示）

/// 描述一个右键菜单项的外观。
/// 可以是单个菜单项，也可以是带子菜单的菜单项。
enum MenuItemRepresentation {
    /// 单个菜单项（标题 + 可选图标）
    case single(title: String, icon: NSImage?)

    /// 带子菜单的菜单项（父标题 + 子项列表）
    /// 子项用 (id, title, icon) 三元组表示，id 用于在回调中区分点击了哪个子项
    case submenu(title: String, icon: NSImage?, children: [(id: String, title: String, icon: NSImage?)])
}

// MARK: - ContextAction 协议

/// 所有右键菜单动作必须遵循的协议。
///
/// ## 如何添加新动作（扩展点）
/// 1. 创建一个新的 struct / class，遵循 `ContextAction`。
/// 2. 实现 `id`、`isVisible(for:)`、`menuItem(for:)`、`perform(context:submenuId:)`。
/// 3. 在 `ActionRegistry.defaultActions` 中添加一行即可。
///
protocol ContextAction {

    // MARK: 标识

    /// 动作的唯一标识符，也用于持久化「启用/禁用」状态。
    /// 建议使用小写 + 点分隔，例如 "action.newFile"。
    var id: String { get }

    /// 动作的显示名称（用于设置界面列表）。
    var displayName: String { get }

    /// 动作的简短描述（用于设置界面列表）。
    var displayDescription: String { get }

    /// 动作的 SF Symbol 图标名称（用于设置界面列表）。
    var sfSymbolName: String { get }

    // MARK: 可见性

    /// 根据当前选择上下文判断此动作是否应显示在右键菜单中。
    ///
    /// - Parameter context: 当前的 Finder 选择上下文。
    /// - Returns: `true` 表示显示，`false` 表示隐藏。
    func isVisible(for context: SelectionContext) -> Bool

    // MARK: 菜单表示

    /// 为当前上下文生成菜单项的表示。
    /// 这决定了在右键菜单中如何呈现此动作（单项 or 子菜单）。
    ///
    /// - Parameter context: 当前的 Finder 选择上下文。
    /// - Returns: 菜单项表示。
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation

    // MARK: 执行

    /// 执行动作。
    ///
    /// - Parameters:
    ///   - context: 当前的 Finder 选择上下文。
    ///   - submenuId: 如果菜单项是子菜单类型，用户点击的子项 id；否则为 nil。
    func perform(context: SelectionContext, submenuId: String?)
}

// MARK: - 协议默认实现

extension ContextAction {

    /// 默认的菜单项表示：使用 displayName 作为标题，无图标。
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        .single(title: displayName, icon: nil)
    }
}

// MARK: - ActionRegistry（动作注册表）

/// 动作注册表 —— 所有可用动作的中心存储。
///
/// ## 如何添加新动作
/// 只需在 `defaultActions` 数组中追加一个新动作实例即可。
/// Finder 扩展和设置界面都从这里读取动作列表。
///
final class ActionRegistry {

    /// 单例
    static let shared = ActionRegistry()

    /// 所有已注册的动作（有序，决定菜单中的显示顺序）。
    private(set) var actions: [ContextAction] = []

    private init() {
        // ⬇️ 这里是注册所有动作的地方 —— 添加新动作只需追加一行
        actions = Self.defaultActions
    }

    /// 默认的动作列表。
    /// ──────────────────────────────
    /// 🔌 扩展点：要添加新动作，在这个数组中追加即可。
    /// ──────────────────────────────
    static var defaultActions: [ContextAction] {
        [
            NewFileAction(),
            NewTerminalWindowAction(),
            NewTerminalTabAction(),
            CopyPathAction(),
            CopyNameAction(),
            AirDropAction(),
            ConvertImageAction(),
            ResizeImageAction(),
        ]
    }

    /// 根据当前上下文和用户设置，筛选出应该显示的动作。
    ///
    /// - Parameters:
    ///   - context: 当前的 Finder 选择上下文。
    ///   - settings: 用户设置（用于判断动作是否被启用）。
    /// - Returns: 应该显示在菜单中的动作列表。
    func visibleActions(for context: SelectionContext, settings: AppSettings) -> [ContextAction] {
        actions.filter { action in
            // 1. 用户是否在设置中启用了此动作
            let enabled = settings.isActionEnabled(action.id)
            // 2. 此动作在当前上下文中是否可见
            let visible = action.isVisible(for: context)
            return enabled && visible
        }
    }

    /// 通过 id 查找动作。
    func action(withId id: String) -> ContextAction? {
        actions.first { $0.id == id }
    }
}
