//
//  FinderSync.swift
//  iMouse – FinderSync Extension
//
//  Finder Sync 扩展的入口文件。
//  职责：
//  1. 监听 Finder 中的文件选择
//  2. 根据 SelectionContext 动态构建右键菜单
//  3. 将菜单点击事件分发给对应的 ContextAction 执行
//
//  ── 架构说明 ──
//  这个文件是 Finder 扩展和 Action 系统之间的「桥梁」。
//  它不包含任何业务逻辑，只负责：
//  - 从 Finder 获取选中的 URL → 构建 SelectionContext
//  - 从 ActionRegistry 获取可见的 Action → 构建 NSMenu
//  - 用户点击菜单项 → 通过 tag 找到对应 Action 并调用 perform()
//
//  ── 监控策略 ──
//  监控根目录 "/" 以覆盖所有文件夹。
//  FinderSync 扩展在沙盒中运行，homeDirectoryForCurrentUser 返回的是
//  容器路径（~/Library/Containers/...），不是真实的用户主目录。
//  所以我们直接使用 "/" 作为监控目录，这样 Finder 中任何位置的右键都能触发。
//
//  ── TCC 安全策略 ──
//  init() 中不访问 App Group UserDefaults / 文件，不做任何跨进程操作。
//  设置在 menu(for:) 时按需加载（用户主动右键触发）。
//

import Cocoa
import FinderSync

// MARK: - FinderSyncExtension

class FinderSyncExtension: FIFinderSync {

    // ── 菜单项映射表 ──
    // 用于将 NSMenuItem 的 tag 映射回对应的 (actionId, submenuId)。
    // 每次构建菜单时重新生成，确保与当前菜单项一一对应。
    private var menuItemMap: [Int: (actionId: String, submenuId: String?)] = [:]

    // ── tag 计数器 ──
    // 每次构建菜单时从 1000 开始递增，避免和系统默认 tag 冲突。
    private var nextTag: Int = 1000

    // ── 记住上次菜单构建时的 menuKind ──
    // 用于在 handleMenuItemClick 中重建正确的 SelectionContext。
    private var lastMenuKind: FIMenuKind?

    // MARK: - 初始化

    override init() {
        super.init()

        // 监控根目录 "/" —— 覆盖所有位置
        //
        // 为什么不用 homeDirectoryForCurrentUser？
        // FinderSync 扩展运行在沙盒容器中，FileManager.default.homeDirectoryForCurrentUser
        // 返回的是容器路径 ~/Library/Containers/com.dogxi.iMouse.FinderSync/Data，
        // 而不是真实的 /Users/username。用容器路径作为监控目录会导致
        // Finder 中的右键菜单完全不显示（因为 Finder 中的路径都不在容器内）。
        //
        // 使用 "/" 作为监控目录是最简单可靠的方案，RClick 等开源项目也使用类似方式。
        let rootURL = URL(fileURLWithPath: "/")
        FIFinderSyncController.default().directoryURLs = [rootURL]

        NSLog("[iMouse FinderSync] 扩展已初始化，监控目录: /")
    }

    // MARK: - 菜单构建

    /// Finder 在用户右键点击时调用此方法来获取上下文菜单。
    ///
    /// 这是整个扩展最核心的方法 —— 它完成以下工作：
    /// 1. 获取 Finder 当前选中的文件 URL 列表
    /// 2. 将 URL 列表包装成 SelectionContext
    /// 3. 从 ActionRegistry 中筛选出对当前上下文可见且已启用的 Action
    /// 4. 为每个可见 Action 生成对应的 NSMenuItem（或子菜单）
    /// 5. 将所有菜单项放在一个 "iMouse" 顶层菜单下返回
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "iMouse")

        // 重置映射表和 tag 计数器
        menuItemMap.removeAll()
        nextTag = 1000

        // 记住当前 menuKind，以便 handleMenuItemClick 能重建正确的 context
        lastMenuKind = menuKind

        // 1. 构建 SelectionContext
        let context = buildSelectionContext(for: menuKind)

        NSLog("[iMouse FinderSync] menu(for: %@) — kind: %@, effectiveDir: %@, targetURL: %@, selectedURLs: %d",
              String(describing: menuKind),
              String(describing: context.kind),
              context.effectiveDirectory?.path(percentEncoded: false) ?? "nil",
              context.currentFolderURL?.path(percentEncoded: false) ?? "nil",
              context.items.count)

        // 2. 加载用户设置（从 App Group 容器文件按需读取）
        let settings = AppSettings.load()
        let showIcons = settings.showMenuIcons

        // 3. 获取所有对当前上下文可见且已启用的 Action
        let visibleActions = ActionRegistry.shared.visibleActions(for: context, settings: settings)

        // 4. 为每个 Action 构建菜单项
        for action in visibleActions {
            let representation = action.menuItem(for: context)

            switch representation {
            case .single(let title, let icon):
                // 单个菜单项
                let item = NSMenuItem(
                    title: title,
                    action: #selector(handleMenuItemClick(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = nextTag
                item.image = showIcons ? resizedIcon(icon) : nil

                // 记录映射：tag → (actionId, nil)
                menuItemMap[nextTag] = (actionId: action.id, submenuId: nil)
                nextTag += 1

                menu.addItem(item)

            case .submenu(let title, let icon, let children):
                // 带子菜单的菜单项
                let parentItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                parentItem.image = showIcons ? resizedIcon(icon) : nil

                let submenu = NSMenu(title: title)
                for child in children {
                    let childItem = NSMenuItem(
                        title: child.title,
                        action: #selector(handleMenuItemClick(_:)),
                        keyEquivalent: ""
                    )
                    childItem.target = self
                    childItem.tag = nextTag
                    childItem.image = showIcons ? resizedIcon(child.icon) : nil

                    // 记录映射：tag → (actionId, child.id)
                    menuItemMap[nextTag] = (actionId: action.id, submenuId: child.id)
                    nextTag += 1

                    submenu.addItem(childItem)
                }

                parentItem.submenu = submenu
                menu.addItem(parentItem)
            }
        }

        // 如果没有任何可见的 Action，显示一个禁用的提示项
        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(
                title: NSLocalizedString("menu.noActions", comment: "无可用操作"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        return menu
    }

    // MARK: - 菜单点击处理

    /// 用户点击右键菜单项时触发。
    ///
    /// 通过 NSMenuItem 的 tag 在 menuItemMap 中查找对应的 Action 和子菜单 ID，
    /// 然后重新构建 SelectionContext，最后调用 Action 的 perform() 方法。
    @objc private func handleMenuItemClick(_ sender: NSMenuItem) {
        let tag = sender.tag

        // 1. 查找映射
        guard let mapping = menuItemMap[tag] else {
            NSLog("[iMouse FinderSync] 未找到 tag=%d 的映射", tag)
            return
        }

        // 2. 查找 Action
        guard let action = ActionRegistry.shared.action(withId: mapping.actionId) else {
            NSLog("[iMouse FinderSync] 未找到 id=%@ 的 Action", mapping.actionId)
            return
        }

        // 3. 重新构建 SelectionContext
        let context = buildSelectionContext(for: lastMenuKind ?? .contextualMenuForItems)

        NSLog("[iMouse FinderSync] 执行动作: %@ (submenuId: %@)",
              mapping.actionId,
              mapping.submenuId ?? "nil")
        NSLog("[iMouse FinderSync] Context kind: %@, effectiveDirectory: %@, currentFolderURL: %@, items count: %d",
              String(describing: context.kind),
              context.effectiveDirectory?.path(percentEncoded: false) ?? "nil",
              context.currentFolderURL?.path(percentEncoded: false) ?? "nil",
              context.items.count)

        // 4. 执行 Action
        action.perform(context: context, submenuId: mapping.submenuId)
    }

    // MARK: - SelectionContext 构建

    /// 从 FIFinderSyncController 获取当前选中的文件 URL 并构建 SelectionContext。
    ///
    /// - Parameter menuKind: 菜单类型，用于区分不同的右键场景：
    ///   - `.contextualMenuForItems`: 右键点击了具体的文件/文件夹
    ///   - `.contextualMenuForContainer`: 右键点击了文件夹窗口的背景（空白处）
    ///   - `.contextualMenuForSidebar`: 右键点击了侧栏项目
    ///   - `.toolbarItemMenu`: 工具栏中的扩展按钮被点击
    ///
    /// - Returns: 根据当前选择构建的 SelectionContext
    private func buildSelectionContext(for menuKind: FIMenuKind) -> SelectionContext {
        let controller = FIFinderSyncController.default()

        // 当前 Finder 窗口正在显示的文件夹 URL
        let targetURL = controller.targetedURL()

        // 用户选中的项目 URL 列表
        let selectedURLs: [URL]
        if let items = controller.selectedItemURLs(), !items.isEmpty {
            selectedURLs = items
        } else {
            selectedURLs = []
        }

        // 根据菜单类型和选择情况决定如何构建 Context
        switch menuKind {
        case .contextualMenuForContainer:
            // 用户右键点击了文件夹窗口的背景（没有选中具体文件）
            if let folder = targetURL {
                return SelectionContext(currentFolderURL: folder)
            }
            return SelectionContext(urls: [], currentFolderURL: nil)

        case .contextualMenuForItems:
            // 用户右键点击了具体的文件/文件夹
            return SelectionContext(urls: selectedURLs, currentFolderURL: targetURL)

        case .contextualMenuForSidebar:
            // 侧栏项目：通常是文件夹
            return SelectionContext(urls: selectedURLs, currentFolderURL: targetURL)

        case .toolbarItemMenu:
            // 工具栏按钮：使用当前窗口的文件夹
            if let folder = targetURL {
                return SelectionContext(currentFolderURL: folder)
            }
            return SelectionContext(urls: [], currentFolderURL: nil)

        @unknown default:
            return SelectionContext(urls: selectedURLs, currentFolderURL: targetURL)
        }
    }

    // MARK: - 图标尺寸调整

    /// 将图标缩放到适合菜单项显示的尺寸（16x16pt）。
    ///
    /// Finder 右键菜单中的图标标准尺寸是 16x16 点。
    /// 如果不调整，SF Symbol 默认尺寸可能太大或太小。
    ///
    /// - Parameter image: 原始图标，可以为 nil
    /// - Returns: 缩放后的图标，如果输入为 nil 则返回 nil
    private func resizedIcon(_ image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        let targetSize = NSSize(width: 16, height: 16)
        image.size = targetSize
        return image
    }
}
