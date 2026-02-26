//
//  SelectionContext.swift
//  iMouse – Shared
//
//  SelectionContext 是关于用户在 Finder 中右键点击了什么的「单一事实来源」。
//  每个 Action 都会收到一个 SelectionContext，用它来决定自己是否应该显示以及该做什么。
//

import Foundation
import UniformTypeIdentifiers

// MARK: - SelectionKind（选择类型）

/// 对当前选择的高级分类，Action 可据此判断自己是否适用。
enum SelectionKind: Equatable {
    case files              // 仅选中了普通文件
    case folders            // 仅选中了文件夹
    case mixed              // 同时选中了文件和文件夹
    case desktop            // 在桌面背景上右键（没有选中具体项目）
    case folderBackground   // 在某个已打开的 Finder 窗口背景上右键
    case none               // 没有选中任何东西 / 未知
}

// MARK: - FileItem（文件项）

/// 对单个选中 URL 的轻量封装，包含缓存的元数据。
struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    // 缓存/派生属性（初始化时计算一次）
    let name: String                  // 例如 "photo.png"
    let nameWithoutExtension: String  // 例如 "photo"
    let pathExtension: String         // 例如 "png"（小写）
    let absolutePath: String          // 例如 "/Users/me/Desktop/photo.png"
    let isDirectory: Bool
    let parentDirectoryURL: URL
    let utType: UTType?               // 统一类型标识符，未知时为 nil

    init(url: URL) {
        self.url = url.standardizedFileURL
        self.absolutePath = self.url.path(percentEncoded: false)
        self.name = self.url.lastPathComponent
        self.pathExtension = self.url.pathExtension.lowercased()
        self.nameWithoutExtension = (self.name as NSString).deletingPathExtension

        // 判断是否为文件夹
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: self.absolutePath, isDirectory: &isDir) {
            self.isDirectory = isDir.boolValue
        } else {
            self.isDirectory = false
        }

        self.parentDirectoryURL = self.url.deletingLastPathComponent()

        // 通过文件扩展名推断 UTType
        if !self.pathExtension.isEmpty {
            self.utType = UTType(filenameExtension: self.pathExtension)
        } else {
            self.utType = nil
        }
    }

    /// 判断此项是否符合给定的 UTType（例如 `.image`）。
    func conforms(to type: UTType) -> Bool {
        guard let utType else { return false }
        return utType.conforms(to: type)
    }

    // Equatable —— 仅按 URL 判断相等性
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - SelectionContext（选择上下文）

/// 描述 Action 需要了解的关于当前 Finder 选择的所有信息。
///
/// 由 Finder Sync 扩展根据收到的 URL 构建，然后传递给每个已注册的
/// `ContextAction`，让它决定是否可见并执行工作。
struct SelectionContext {

    /// 选中的各个项目，已包装为 `FileItem`。
    let items: [FileItem]

    /// Finder 窗口当前文件夹的 URL（Finder Sync 中称为 "target"）。
    /// 即使没有明确选中任何项目，这也是用户正在查看的文件夹。
    let currentFolderURL: URL?

    /// 派生的选择类型
    let kind: SelectionKind

    // MARK: 便捷查询

    /// 所有选中的 URL
    var urls: [URL] { items.map(\.url) }

    /// 仅包含普通文件（非文件夹）的项目
    var files: [FileItem] { items.filter { !$0.isDirectory } }

    /// 仅包含文件夹的项目
    var folders: [FileItem] { items.filter { $0.isDirectory } }

    /// 符合 `.image` 的项目（PNG、JPEG、WEBP、TIFF 等）
    var imageFiles: [FileItem] { items.filter { $0.conforms(to: .image) } }

    /// 返回「有效工作目录」：
    /// - 如果选中了单个文件夹 → 该文件夹
    /// - 如果选中了文件 → 第一个文件的父目录
    /// - 否则 → `currentFolderURL`
    var effectiveDirectory: URL? {
        if let first = items.first {
            return first.isDirectory ? first.url : first.parentDirectoryURL
        }
        return currentFolderURL
    }

    /// 当所有选中项都是图片时为 `true`
    var allImages: Bool {
        !items.isEmpty && items.allSatisfy { $0.conforms(to: .image) }
    }

    /// 当至少有一个选中项是图片时为 `true`
    var hasImages: Bool {
        items.contains { $0.conforms(to: .image) }
    }

    /// 选中项是否为空（背景点击）
    var isEmpty: Bool {
        items.isEmpty
    }

    // MARK: 初始化

    /// 从选中的 URL 列表创建上下文
    init(urls: [URL], currentFolderURL: URL? = nil) {
        self.items = urls.map { FileItem(url: $0) }
        self.currentFolderURL = currentFolderURL
        self.kind = Self.resolveKind(items: self.items, folderURL: currentFolderURL)
    }

    /// 空上下文（例如：在文件夹背景上点击）
    init(currentFolderURL: URL) {
        self.items = []
        self.currentFolderURL = currentFolderURL
        self.kind = .folderBackground
    }

    // MARK: 私有方法

    /// 根据选中项和当前文件夹 URL 推断 SelectionKind
    private static func resolveKind(items: [FileItem], folderURL: URL?) -> SelectionKind {
        guard !items.isEmpty else {
            // 没有选中任何项目 —— 判断是桌面还是文件夹背景
            if let folder = folderURL {
                let desktopPath = FileManager.default
                    .urls(for: .desktopDirectory, in: .userDomainMask)
                    .first?.path(percentEncoded: false)
                if folder.path(percentEncoded: false) == desktopPath {
                    return .desktop
                }
                return .folderBackground
            }
            return .none
        }

        let hasFiles = items.contains { !$0.isDirectory }
        let hasFolders = items.contains { $0.isDirectory }

        switch (hasFiles, hasFolders) {
        case (true, true):   return .mixed
        case (true, false):  return .files
        case (false, true):  return .folders
        default:             return .none
        }
    }
}
