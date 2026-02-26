//
//  AppSettings.swift
//  iMouse – Shared
//
//  用户偏好设置模型。
//  通过 App Group 容器中的 plist 文件实现主 App 和 Finder 扩展之间的设置共享。
//  所有设置变更会自动持久化。
//
//  ── 架构说明 ──
//  主 App 不启用沙盒（与 RClick 相同做法）。
//  **不使用 UserDefaults(suiteName:)** —— 因为在非沙盒 App 中，
//  UserDefaults(suiteName:) 会走 CFPreferences 的 kCFPreferencesAnyUser 路径，
//  系统将其视为跨进程数据访问，触发 kTCCServiceSystemPolicyAppData 弹窗。
//
//  解决方案：直接读写 App Group 容器目录中的 plist 文件。
//  App Group 容器路径通过 FileManager.containerURL(forSecurityApplicationGroupIdentifier:) 获取。
//  这个路径对主 App 和 FinderSync 扩展都可访问，且不经过 CFPreferences，不触发 TCC。
//

import Foundation

// MARK: - 常量

/// App Group 标识符 —— 主 App 和 Finder Sync 扩展必须使用同一个 App Group
let kAppGroupIdentifier = "group.com.dogxi.iMouse"

/// 设置文件名（保存在 App Group 容器目录中）
private let kSettingsFileName = "com.dogxi.iMouse.settings.json"

// MARK: - AppLanguage（应用语言）

/// 应用界面语言设置
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system = "system"   // 跟随系统
    case english = "en"      // English
    case chinese = "zh-Hans" // 简体中文

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:  return NSLocalizedString("settings.language.system", comment: "Follow System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    /// 返回用于 Bundle 查找的语言代码，nil 表示跟随系统
    var localeIdentifier: String? {
        switch self {
        case .system:  return nil
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }
}

// MARK: - NewFileType（新建文件类型）

/// 新建文件时使用的默认文件类型
struct NewFileTemplate: Codable, Equatable, Identifiable {
    var id: String { extension_ }
    let extension_: String   // 例如 "txt"、"md"、"py"
    let displayName: String  // 例如 "文本文件"、"Markdown"

    enum CodingKeys: String, CodingKey {
        case extension_ = "ext"
        case displayName = "name"
    }
}

// MARK: - ImageFormat（图片格式）

/// 支持的图片转换格式
enum ImageFormat: String, Codable, CaseIterable, Identifiable {
    case png  = "png"
    case jpeg = "jpeg"
    case webp = "webp"
    case tiff = "tiff"
    case heic = "heic"
    case gif  = "gif"
    case bmp  = "bmp"

    var id: String { rawValue }

    /// 人类可读的显示名称
    var displayName: String {
        switch self {
        case .png:  return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        case .tiff: return "TIFF"
        case .heic: return "HEIC"
        case .gif:  return "GIF"
        case .bmp:  return "BMP"
        }
    }

    /// 对应的文件扩展名
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default:    return rawValue
        }
    }
}

// MARK: - ImageResizeOption（图片缩放选项）

/// 图片缩放的预设尺寸
struct ImageResizeOption: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String       // 显示名称，例如 "512 × 512" 或 "50%"
    var kind: Kind

    enum Kind: Codable, Equatable, Hashable {
        /// 按目标宽度缩放（保持宽高比）
        case width(Int)
        /// 按百分比缩放
        case percentage(Int)
        /// 按指定宽度和高度缩放（不保持宽高比）
        case dimensions(width: Int, height: Int)
    }
}

extension ImageResizeOption: Equatable {
    /// 比较时忽略 id（UUID），只比较用户可见的内容
    static func == (lhs: ImageResizeOption, rhs: ImageResizeOption) -> Bool {
        lhs.label == rhs.label && lhs.kind == rhs.kind
    }
}

// MARK: - PathSeparator（多路径分隔符）

/// 当选中多个文件时，复制路径使用的分隔符
enum PathSeparator: String, Codable, CaseIterable, Identifiable {
    case newline = "newline"   // 换行符
    case comma   = "comma"     // 逗号
    case space   = "space"     // 空格
    case tab     = "tab"       // Tab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newline: return NSLocalizedString("settings.separator.newline", comment: "换行")
        case .comma:   return NSLocalizedString("settings.separator.comma", comment: "逗号")
        case .space:   return NSLocalizedString("settings.separator.space", comment: "空格")
        case .tab:     return NSLocalizedString("settings.separator.tab", comment: "Tab")
        }
    }

    var character: String {
        switch self {
        case .newline: return "\n"
        case .comma:   return ", "
        case .space:   return " "
        case .tab:     return "\t"
        }
    }
}

// MARK: - CopyNameMode（复制名称模式）

/// 复制文件/文件夹名称时是否包含扩展名
enum CopyNameMode: String, Codable, CaseIterable, Identifiable {
    case withExtension    = "withExt"    // 包含扩展名，例如 "photo.png"
    case withoutExtension = "withoutExt" // 不含扩展名，例如 "photo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .withExtension:    return NSLocalizedString("settings.copyName.withExt", comment: "包含扩展名")
        case .withoutExtension: return NSLocalizedString("settings.copyName.withoutExt", comment: "不含扩展名")
        }
    }
}

// MARK: - TerminalApp（终端应用）

/// 预定义的终端应用选项
enum TerminalApp: String, Codable, CaseIterable, Identifiable {
    case ghostty  = "ghostty"
    case terminal = "terminal"   // macOS Terminal.app
    case iterm2   = "iterm2"     // iTerm2
    case warp     = "warp"       // Warp
    case kitty    = "kitty"      // Kitty
    case alacritty = "alacritty" // Alacritty
    case custom   = "custom"     // 自定义

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ghostty:    return "Ghostty"
        case .terminal:   return "Terminal"
        case .iterm2:     return "iTerm2"
        case .warp:       return "Warp"
        case .kitty:      return "Kitty"
        case .alacritty:  return "Alacritty"
        case .custom:     return NSLocalizedString("settings.terminal.custom", comment: "Custom")
        }
    }

    /// 该终端应用的默认 bundle identifier（用于通过 NSWorkspace 检测是否安装）
    var bundleIdentifier: String? {
        switch self {
        case .ghostty:    return "com.mitchellh.ghostty"
        case .terminal:   return "com.apple.Terminal"
        case .iterm2:     return "com.googlecode.iterm2"
        case .warp:       return "dev.warp.Warp-Stable"
        case .kitty:      return "net.kovidgoyal.kitty"
        case .alacritty:  return "org.alacritty"
        case .custom:     return nil
        }
    }

    /// 该终端应用的默认可执行文件搜索路径
    var defaultSearchPaths: [String] {
        switch self {
        case .ghostty:
            return [
                "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                "/usr/local/bin/ghostty",
                "/opt/homebrew/bin/ghostty",
            ]
        case .terminal:
            return ["/System/Applications/Utilities/Terminal.app"]
        case .iterm2:
            return ["/Applications/iTerm.app"]
        case .warp:
            return ["/Applications/Warp.app"]
        case .kitty:
            return [
                "/Applications/kitty.app/Contents/MacOS/kitty",
                "/usr/local/bin/kitty",
                "/opt/homebrew/bin/kitty",
            ]
        case .alacritty:
            return [
                "/Applications/Alacritty.app/Contents/MacOS/alacritty",
                "/usr/local/bin/alacritty",
                "/opt/homebrew/bin/alacritty",
            ]
        case .custom:
            return []
        }
    }
}

// MARK: - AppSettings（应用设置）

/// iMouse 的全部用户设置。
///
/// 通过 `Codable` 序列化为 JSON 并保存在 App Group 容器目录的文件中，
/// 这样主 App 和 Finder Sync 扩展就能共享同一份设置。
///
/// **不使用 UserDefaults(suiteName:)** —— 避免 CFPreferences 触发 TCC。
struct AppSettings: Codable, Equatable {

    // ─── 动作启用/禁用状态 ───────────────────────────

    /// 记录每个动作是否启用。Key = ContextAction.id, Value = 是否启用。
    /// 默认情况下，不在此字典中的动作视为已启用。
    var actionEnabledStates: [String: Bool] = [:]

    // ─── 语言设置 ───────────────────────────────────

    /// 应用界面语言
    var language: AppLanguage = .system

    // ─── New File 设置 ──────────────────────────────

    /// 新建文件时使用的默认扩展名
    var defaultNewFileExtension: String = "txt"

    /// 预设的新建文件模板（出现在子菜单中）
    var newFileTemplates: [NewFileTemplate] = Self.defaultNewFileTemplates

    // ─── Copy Path 设置 ─────────────────────────────

    /// 多文件路径的分隔符
    var pathSeparator: PathSeparator = .newline

    // ─── Copy Name 设置 ─────────────────────────────

    /// 复制名称时是否包含扩展名
    var copyNameMode: CopyNameMode = .withExtension

    // ─── Convert Image 设置 ─────────────────────────

    /// 「转换为」菜单中显示的格式列表
    var enabledImageFormats: [ImageFormat] = [.png, .jpeg, .webp, .heic]

    /// 转换后的图片质量（0.0 ~ 1.0），仅对 JPEG / HEIC 等有损格式生效
    var imageConversionQuality: Double = 0.85

    // ─── Resize Image 设置 ──────────────────────────

    /// 「调整大小」菜单中显示的预设尺寸选项
    var resizeOptions: [ImageResizeOption] = Self.defaultResizeOptions

    // ─── 终端设置 ───────────────────────────────────

    /// 选择的终端应用
    var terminalApp: TerminalApp = .ghostty

    /// 终端应用的自定义路径（为空时自动检测）
    var terminalCustomPath: String = ""

    /// 向后兼容：旧的 ghosttyPath 字段
    var ghosttyPath: String = ""

    // ─── 通用设置 ───────────────────────────────────

    /// 是否在菜单项旁显示图标
    var showMenuIcons: Bool = true

    // ─── 计算属性 ───────────────────────────────────

    /// 获取当前终端应用的有效路径
    var effectiveTerminalPath: String {
        if !terminalCustomPath.isEmpty {
            return terminalCustomPath
        }
        if terminalApp == .ghostty && !ghosttyPath.isEmpty {
            return ghosttyPath
        }
        return ""
    }
}

// MARK: - 默认值

extension AppSettings {

    /// 默认的新建文件模板
    static let defaultNewFileTemplates: [NewFileTemplate] = [
        NewFileTemplate(extension_: "txt", displayName: "Text"),
        NewFileTemplate(extension_: "md",  displayName: "Markdown"),
        NewFileTemplate(extension_: "py",  displayName: "Python"),
        NewFileTemplate(extension_: "sh",  displayName: "Shell"),
        NewFileTemplate(extension_: "json", displayName: "JSON"),
        NewFileTemplate(extension_: "html", displayName: "HTML"),
        NewFileTemplate(extension_: "css",  displayName: "CSS"),
        NewFileTemplate(extension_: "js",   displayName: "JavaScript"),
        NewFileTemplate(extension_: "swift", displayName: "Swift"),
    ]

    /// 默认的缩放选项
    static let defaultResizeOptions: [ImageResizeOption] = [
        ImageResizeOption(label: "256 × 256",   kind: .dimensions(width: 256,  height: 256)),
        ImageResizeOption(label: "512 × 512",   kind: .dimensions(width: 512,  height: 512)),
        ImageResizeOption(label: "1024 × 1024", kind: .dimensions(width: 1024, height: 1024)),
        ImageResizeOption(label: "2048 × 2048", kind: .dimensions(width: 2048, height: 2048)),
        ImageResizeOption(label: "75%",         kind: .percentage(75)),
        ImageResizeOption(label: "50%",         kind: .percentage(50)),
        ImageResizeOption(label: "25%",         kind: .percentage(25)),
    ]
}

// MARK: - 动作启用状态查询

extension AppSettings {

    /// 查询某个动作是否已启用。
    func isActionEnabled(_ actionId: String) -> Bool {
        actionEnabledStates[actionId] ?? true
    }

    /// 设置某个动作的启用状态。
    mutating func setActionEnabled(_ actionId: String, enabled: Bool) {
        actionEnabledStates[actionId] = enabled
    }
}

// MARK: - 语言辅助

extension AppSettings {

    /// 根据当前语言设置获取本地化字符串
    static func localizedString(_ key: String, comment: String = "") -> String {
        let settings = load()
        if let localeId = settings.language.localeIdentifier,
           let path = Bundle.main.path(forResource: localeId, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return NSLocalizedString(key, comment: comment)
    }

    /// 为 Finder 扩展提供的本地化方法
    static func localizedString(_ key: String, comment: String = "", bundle: Bundle) -> String {
        let settings = load()
        if let localeId = settings.language.localeIdentifier,
           let path = bundle.path(forResource: localeId, ofType: "lproj"),
           let locBundle = Bundle(path: path) {
            return locBundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - 文件路径辅助

extension AppSettings {

    /// 获取 App Group 容器中设置文件的完整路径。
    ///
    /// 使用 FileManager.containerURL(forSecurityApplicationGroupIdentifier:) 获取
    /// App Group 共享容器的 URL，然后在其中创建/读取设置文件。
    ///
    /// 这种方式绕过了 CFPreferences / UserDefaults 的 TCC 检查，
    /// 因为我们只是在自己的 App Group 容器中读写普通文件。
    private static func settingsFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: kAppGroupIdentifier
        ) else {
            NSLog("[iMouse] ⚠️ 无法获取 App Group 容器路径: %@", kAppGroupIdentifier)
            return nil
        }
        return containerURL.appendingPathComponent(kSettingsFileName)
    }
}

// MARK: - 持久化（JSON 文件 in App Group container）

extension AppSettings {

    /// 从 App Group 容器中的 JSON 文件加载设置。
    /// 如果文件不存在或解析失败，返回默认设置。
    ///
    /// **不使用 UserDefaults(suiteName:)** —— 避免触发 TCC 弹窗。
    static func load() -> AppSettings {
        guard let fileURL = settingsFileURL() else {
            return AppSettings()
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)

            // 向后兼容迁移：如果旧的 ghosttyPath 有值但新的 terminalCustomPath 为空
            if settings.terminalApp == .ghostty && settings.terminalCustomPath.isEmpty && !settings.ghosttyPath.isEmpty {
                settings.terminalCustomPath = settings.ghosttyPath
            }

            // 向后兼容迁移：将旧的 action.newGhosttyWindow 启用状态迁移到新的两个动作 ID
            if let oldState = settings.actionEnabledStates.removeValue(forKey: "action.newGhosttyWindow") {
                if settings.actionEnabledStates["action.terminalWindow"] == nil {
                    settings.actionEnabledStates["action.terminalWindow"] = oldState
                }
                if settings.actionEnabledStates["action.terminalTab"] == nil {
                    settings.actionEnabledStates["action.terminalTab"] = oldState
                }
                settings.save()
            }
            return settings
        } catch {
            NSLog("[iMouse] 设置加载失败，使用默认值: %@", error.localizedDescription)
            return AppSettings()
        }
    }

    /// 将当前设置保存到 App Group 容器中的 JSON 文件。
    ///
    /// **不使用 UserDefaults(suiteName:)** —— 避免触发 TCC 弹窗。
    func save() {
        guard let fileURL = AppSettings.settingsFileURL() else {
            NSLog("[iMouse] 无法获取设置文件路径，设置未保存。")
            return
        }

        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[iMouse] 设置保存失败: %@", error.localizedDescription)
        }
    }

    /// 恢复为默认设置
    static func resetToDefaults() -> AppSettings {
        let settings = AppSettings()
        settings.save()
        return settings
    }
}

// MARK: - SettingsManager（设置管理器）

/// 提供响应式的设置管理，主要用于 SwiftUI 界面。
/// 它是一个 ObservableObject，任何设置的变更都会自动触发 UI 刷新并持久化。
@MainActor
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    /// 当前设置 —— 修改后自动保存
    @Published var settings: AppSettings {
        didSet {
            if settings != oldValue {
                settings.save()
                // 如果语言设置改变，更新应用的语言偏好
                if settings.language != oldValue.language {
                    applyLanguage(settings.language)
                }
            }
        }
    }

    private init() {
        self.settings = AppSettings.load()
        // 启动时应用语言设置
        applyLanguage(self.settings.language)
    }

    /// 重置为默认设置
    func resetToDefaults() {
        settings = AppSettings.resetToDefaults()
    }

    /// 应用语言设置
    /// 通过修改 AppleLanguages 用户默认值来影响 NSLocalizedString 的行为
    private func applyLanguage(_ language: AppLanguage) {
        if let localeId = language.localeIdentifier {
            UserDefaults.standard.set([localeId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        // 不调用 synchronize() — UserDefaults.standard 是进程本地的，不涉及 App Group
    }
}
