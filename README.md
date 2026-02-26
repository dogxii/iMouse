# 🖱️ iMouse — Super Right Click for Finder

> 一个原生 macOS 应用，通过 Finder Sync Extension 增强 Finder 右键菜单，提供新建文件、打开终端、复制路径、AirDrop、图片转换/缩放等实用功能。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-purple?style=flat-square" />
  <img src="https://img.shields.io/badge/version-1.1.0-green?style=flat-square" />
  <img src="https://img.shields.io/badge/language-中文%20%7C%20English-lightgrey?style=flat-square" />
</p>

---

## 目录

- [功能概览](#功能概览)
- [技术架构](#技术架构)
- [项目结构](#项目结构)
- [环境要求](#环境要求)
- [构建与运行](#构建与运行)
- [架构详解](#架构详解)
- [8 个内置动作](#8-个内置动作)
- [如何添加新动作](#如何添加新动作)
- [安全与权限](#安全与权限)
- [调试指南](#调试指南)
- [常见问题 (FAQ)](#常见问题-faq)
- [更新日志](#更新日志)

---

## 功能概览

| #   | 功能               | 说明                                                                                                                  |
| --- | ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| 1   | **新建文件**       | 在当前文件夹中创建空白文件，支持多种模板（txt、md、py、json…），自动避免文件名冲突                                    |
| 2   | **新建终端窗口**   | 在选中文件夹（或文件所在目录）打开终端新窗口，支持 Ghostty、iTerm2、Terminal.app、Warp、Kitty、Alacritty 及自定义终端 |
| 3   | **新建终端标签页** | 在选中位置打开终端新标签页（不支持标签的终端自动降级为新窗口）                                                        |
| 4   | **复制路径**       | 将选中文件/文件夹的绝对路径复制到剪贴板，支持多选和自定义分隔符                                                       |
| 5   | **复制名称**       | 复制文件/文件夹名称，可配置是否包含扩展名                                                                             |
| 6   | **AirDrop**        | 通过 NSSharingService 快速 AirDrop 选中的文件                                                                         |
| 7   | **转换图片格式**   | 将图片转换为 PNG/JPEG/WebP/HEIC/TIFF/GIF/BMP，使用 CoreGraphics + ImageIO                                             |
| 8   | **调整图片大小**   | 按预设尺寸（像素宽度或百分比）缩放图片，保持宽高比                                                                    |

---

## 技术架构

### 为什么选择 Finder Sync Extension？

macOS 提供了两种方式扩展 Finder 右键菜单：

| 方式                         | 优点                          | 缺点                                          |
| ---------------------------- | ----------------------------- | --------------------------------------------- |
| **Finder Sync Extension** ✅ | 原生 API、稳定、跨 macOS 版本 | 沙盒限制（已通过 URL scheme 委托主 App 解决） |
| Action Extension             | 简单                          | 仅支持文件操作，无法自定义 UI                 |

iMouse 选择 **Finder Sync Extension**，因为它能够：

- 在任意文件夹右键时触发（不仅限于选中文件）
- 动态构建菜单（根据选中内容调整菜单项）
- 通过 `ContextAction` 协议实现高度可扩展的插件式架构

### 整体流程

```
用户右键点击 Finder
       │
       ▼
FinderSyncExtension.menu(for:)
       │  构建 SelectionContext
       │  查询 ActionRegistry
       ▼
NSMenu（动态构建）
       │
       │ 用户点击菜单项
       ▼
ContextAction.perform(context:submenuId:)
       │
       ├─ NewFileAction           → FileManager 创建文件
       ├─ NewTerminalWindowAction → imouse://terminal URL scheme → 主 App → NSWorkspace.open
       ├─ NewTerminalTabAction    → imouse://terminal URL scheme → 主 App → NSWorkspace.open
       ├─ CopyPathAction          → NSPasteboard 写入路径
       ├─ CopyNameAction          → NSPasteboard 写入名称
       ├─ AirDropAction           → imouse://airdrop URL scheme → 主 App → NSSharingService
       ├─ ConvertImageAction      → CoreGraphics + ImageIO 转换
       └─ ResizeImageAction       → CGContext 缩放
```

---

## 项目结构

```
iMouse/
│
├── project.yml                  # XcodeGen 项目配置文件
├── setup.sh                     # 项目初始化脚本（首次使用）
├── scripts/
│   └── build.sh                 # 一键构建 & 安装脚本
│
├── Config/                      # 📋 构建配置（Info.plist / Entitlements）
│   ├── iMouse-Info.plist
│   ├── iMouse.entitlements
│   ├── FinderSync-Info.plist
│   └── FinderSync.entitlements
│
├── Shared/                      # 🔗 共享核心代码（主 App + 扩展共用）
│   ├── SelectionContext.swift   #   选择上下文模型
│   ├── ContextAction.swift      #   动作协议 + ActionRegistry
│   └── AppSettings.swift        #   设置模型 + 持久化
│
├── iMouse/                      # 📱 主 App
│   ├── iMouseApp.swift          #   App 入口 + 菜单栏
│   │
│   ├── Core/                    #   核心业务逻辑
│   │   └── Actions/             #   🔌 所有动作实现（扩展点！）
│   │       ├── NewFileAction.swift
│   │       ├── NewGhosttyWindowAction.swift   # 终端动作（支持多终端）
│   │       ├── CopyPathAction.swift
│   │       ├── CopyNameAction.swift
│   │       ├── AirDropAction.swift
│   │       ├── ConvertImageAction.swift
│   │       └── ResizeImageAction.swift
│   │
│   ├── UI/                      #   SwiftUI 界面
│   │   └── SettingsView.swift   #   设置窗口（6 个标签页）
│   │
│   └── Resources/               #   资源文件
│       ├── en.lproj/
│       │   └── Localizable.strings    # 英文翻译
│       └── zh-Hans.lproj/
│           └── Localizable.strings    # 简体中文翻译
│
└── FinderSync/                  # 🧩 Finder Sync Extension
    ├── FinderSync.swift         #   扩展入口（菜单构建 + 事件分发）
    └── Resources/               #   扩展资源
        ├── en.lproj/
        │   └── Localizable.strings
        └── zh-Hans.lproj/
            └── Localizable.strings
```

---

## 环境要求

| 要求                                              | 最低版本                     |
| ------------------------------------------------- | ---------------------------- |
| macOS                                             | 14.0 Sonoma                  |
| Xcode                                             | 15.0+                        |
| Swift                                             | 5.9+                         |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 2.38+（用于生成 .xcodeproj） |

---

## 构建与运行

### 首次初始化（生成 Xcode 项目）

```bash
cd iMouse
chmod +x setup.sh
./setup.sh
```

脚本会自动检测并安装 XcodeGen，然后生成 `iMouse.xcodeproj`。

### Xcode 配置

1. **选择开发团队**：在两个 target（`iMouse` + `FinderSyncExt`）的 Signing & Capabilities 中设置你的 Team
2. **配置 App Group**：为两个 target 都添加 App Group `group.com.dogxi.iMouse`
3. **构建运行**：选择 `iMouse` scheme，按 ⌘R

### 一键构建 & 安装（推荐日常使用）

每次修改代码后，运行以下命令即可自动完成**构建 → 停止旧进程 → 安装到 /Applications → 重启**：

```bash
./scripts/build.sh
```

脚本使用本地 Apple Development 签名，无需手动操作 Xcode。

### 手动构建

```bash
xcodebuild \
  -project iMouse.xcodeproj \
  -scheme iMouse \
  -configuration Release \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=<你的 Team ID> \
  CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates
```

### 启用 Finder Sync 扩展

构建成功后，需要手动启用扩展：

**方法 A — 系统设置：**

1. 打开「系统设置 → 隐私与安全 → 扩展 → 已添加的扩展」
2. 找到 `iMouse` 并启用

**方法 B — 命令行：**

```bash
pluginkit -e use -i com.dogxi.iMouse.FinderSync
```

**方法 C — 如果扩展不出现：**

```bash
killall Finder
pluginkit -m -v -i com.dogxi.iMouse.FinderSync
```

---

## 架构详解

### SelectionContext

`SelectionContext` 封装了 Finder 中的当前选择状态，是各个 `ContextAction` 做决策的依据：

```swift
struct SelectionContext {
    enum Kind {
        case none           // 无选中项
        case files          // 选中了文件（含混合）
        case folders        // 选中了文件夹
        case mixed          // 文件 + 文件夹混选
        case folderBackground // 右键点击文件夹窗口背景
        case desktop        // 右键点击桌面
    }

    var kind: Kind
    var items: [URL]            // 选中的项目 URL 列表
    var currentFolderURL: URL?  // 当前 Finder 窗口所在文件夹

    // 计算属性：动作应该在哪个目录下执行
    var effectiveDirectory: URL? { ... }
}
```

**关键属性 `effectiveDirectory`：**

- 选中文件夹 → 返回该文件夹
- 选中文件 → 返回文件所在目录
- 背景右键 → 返回当前窗口文件夹
- 多选混合 → 返回第一个有效目录

### ContextAction 协议

所有动作的统一接口：

```swift
protocol ContextAction {
    var id: String { get }                    // 唯一标识，用于持久化启用状态
    var displayName: String { get }           // 设置界面显示名称
    var displayDescription: String { get }    // 设置界面描述
    var sfSymbolName: String { get }          // 设置界面图标

    func isVisible(for context: SelectionContext) -> Bool
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation
    func perform(context: SelectionContext, submenuId: String?)
}
```

`MenuItemRepresentation` 支持两种形式：

```swift
enum MenuItemRepresentation {
    case single(title: String, icon: NSImage?)
    case submenu(title: String, icon: NSImage?, children: [(id: String, title: String, icon: NSImage?)])
}
```

### ActionRegistry

动作注册表——所有动作的中心存储，也是**扩展点**：

```swift
final class ActionRegistry {
    static let shared = ActionRegistry()

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
            // ← 在这里添加新动作
        ]
    }
}
```

### Finder Sync Extension

`FinderSyncExtension` 是 Finder 和 Action 系统之间的桥梁，不包含任何业务逻辑：

1. `menu(for:)` → 从 `ActionRegistry` 获取可见动作 → 构建 `NSMenu`
2. `handleMenuItemClick(_:)` → 通过 tag 找到对应 Action → 调用 `perform()`

### 终端启动机制

FinderSync 扩展运行在**沙盒化的 XPC 插件进程**中，无法可靠地直接启动终端应用（`NSWorkspace.shared.open` 在沙盒中传递 arguments / 工作目录不可靠）。

参考 [RClick](https://github.com/wflixu/RClick) 的委托模式（RClick 使用 `DistributedNotificationCenter`），iMouse 改用 **URL scheme** 将请求从沙盒扩展转发到非沙盒的主 App 进程：

```
FinderSync 扩展（沙盒）              主 App（非沙盒）
       │                                    │
       │  imouse://terminal?dir=/path&tab=0  │
       │ ──────────────────────────────────> │
       │                                    │
       │                          TerminalLauncher.launch()
       │                          NSWorkspace.shared.open(
       │                              [dirURL],
       │                              withApplicationAt: appURL,
       │                              configuration: config
       │                          )
```

这与 AirDrop 动作（`imouse://airdrop?files=...`）使用相同的委托模式。

优势：

- 主 App 非沙盒，`NSWorkspace.open` 可靠传递目录参数
- 不需要 AppleScript、Automation 权限或 Apple Events
- 不需要 `DistributedNotificationCenter`（避免触发 TCC 弹窗）
- 不需要创建临时 `.command` 脚本
- 终端应用原生处理目录参数，cd 行为可靠
- NSWorkspace 失败时自动降级到 `/usr/bin/open` 命令

**支持的终端：**

| 终端         | Bundle ID               | 窗口 | 标签页   |
| ------------ | ----------------------- | ---- | -------- |
| Ghostty      | `com.mitchellh.ghostty` | ✅   | ↗ 新窗口 |
| Terminal.app | `com.apple.Terminal`    | ✅   | ↗ 新窗口 |
| iTerm2       | `com.googlecode.iterm2` | ✅   | ↗ 新窗口 |
| Warp         | `dev.warp.Warp-Stable`  | ✅   | ↗ 新窗口 |
| Kitty        | `net.kovidgoyal.kitty`  | ✅   | ↗ 新窗口 |
| Alacritty    | `org.alacritty`         | ✅   | ↗ 新窗口 |
| 自定义       | —                       | ✅   | ✅       |

> 标签页因沙盒限制无法通过 AppleScript/System Events 控制，故统一降级为新窗口。

### 设置系统

设置通过 `AppSettings` 结构体持久化为 **App Group 容器中的 JSON 文件**：

```swift
// 主 App 读写
var settings = AppSettings.load()
settings.terminalApp = .ghostty
settings.save()

// Finder 扩展读取（跨进程共享，通过 App Group 容器 JSON 文件）
let settings = AppSettings.load()
```

> **为什么不用 `UserDefaults(suiteName:)`？**
> 在非沙盒主 App 中，`UserDefaults(suiteName:)` 会走 CFPreferences 的 `kCFPreferencesAnyUser` 路径，系统将其视为跨进程数据访问，触发 `kTCCServiceSystemPolicyAppData` 的 TCC 授权弹窗。
> 改为直接在 App Group 容器目录（`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`）读写 JSON 文件，绕过 CFPreferences，不触发 TCC。

### 国际化 (i18n)

所有用户可见的字符串都通过 `NSLocalizedString` 提取，支持英文和简体中文：

```
iMouse/Resources/en.lproj/Localizable.strings      # 英文
iMouse/Resources/zh-Hans.lproj/Localizable.strings  # 简体中文
FinderSync/Resources/en.lproj/Localizable.strings   # 扩展英文
FinderSync/Resources/zh-Hans.lproj/Localizable.strings
```

---

## 8 个内置动作

### 1. NewFileAction — 新建文件

| 属性     | 值                               |
| -------- | -------------------------------- |
| ID       | `action.newFile`                 |
| 可见条件 | 有当前文件夹（背景右键或选中项） |
| 菜单形式 | 子菜单（列出所有模板）           |

**行为：**

- 在当前文件夹下创建对应扩展名的空白文件
- 支持自定义模板列表（可在设置中添加/删除）
- 自动处理文件名冲突（追加 \_1, \_2 等后缀）

### 2. NewTerminalWindowAction — 新建终端窗口

| 属性     | 值                                 |
| -------- | ---------------------------------- |
| ID       | `action.terminalWindow`            |
| 可见条件 | 几乎所有情况（除了 `.none`）       |
| 菜单形式 | 单项（标题随当前终端设置动态变化） |

**行为：**

- 选中文件夹 → 在该文件夹中打开终端新窗口
- 选中文件 → 在文件所在目录打开终端新窗口
- 背景点击 → 在当前 Finder 窗口文件夹打开终端新窗口

### 3. NewTerminalTabAction — 新建终端标签页

| 属性     | 值                           |
| -------- | ---------------------------- |
| ID       | `action.terminalTab`         |
| 可见条件 | 几乎所有情况（除了 `.none`） |
| 菜单形式 | 单项                         |

与新建窗口行为相同，但尝试在已有窗口中打开新标签页。

### 4. CopyPathAction — 复制路径

| 属性     | 值                                 |
| -------- | ---------------------------------- |
| ID       | `action.copyPath`                  |
| 可见条件 | 有选中项，或背景点击且有当前文件夹 |
| 菜单形式 | 单项                               |

**行为：**

- 将所有选中项的绝对 POSIX 路径复制到剪贴板
- 多选时用设置中配置的分隔符连接（默认换行）
- 支持路径格式：原始 / 转义空格 / 带引号

### 5. CopyNameAction — 复制名称

| 属性     | 值                                 |
| -------- | ---------------------------------- |
| ID       | `action.copyName`                  |
| 可见条件 | 有选中项，或背景点击且有当前文件夹 |
| 菜单形式 | 单项                               |

**行为：**

- 复制文件/文件夹名称（不含路径）
- 可配置是否包含扩展名：`photo.png` vs `photo`
- 多选时用分隔符连接

### 6. AirDropAction — AirDrop

| 属性     | 值                   |
| -------- | -------------------- |
| ID       | `action.airDrop`     |
| 可见条件 | 有选中的文件或文件夹 |
| 菜单形式 | 单项                 |

**行为：**

- 使用 `NSSharingService(named: .sendViaAirDrop)` 调用系统 AirDrop
- 会弹出系统的 AirDrop 设备选择器窗口

### 7. ConvertImageAction — 转换图片格式

| 属性     | 值                           |
| -------- | ---------------------------- |
| ID       | `action.convertImage`        |
| 可见条件 | 选中项包含至少一个图片文件   |
| 菜单形式 | 子菜单（列出所有启用的格式） |

**支持格式：**

| 格式 | 有损/无损 | 备注                   |
| ---- | --------- | ---------------------- |
| PNG  | 无损      | 支持透明               |
| JPEG | 有损      | 质量可配置             |
| WebP | 有损      | macOS 14+ 原生支持     |
| HEIC | 有损      | Apple 格式，质量可配置 |
| TIFF | 无损      | 大文件                 |
| GIF  | 无损      | 仅支持单帧             |
| BMP  | 无损      | 大文件                 |

**行为：**

- 使用 CoreGraphics + ImageIO 转换（零第三方依赖）
- 输出文件：`photo.jpg`（不冲突）或 `photo_converted.jpg`
- 跳过已是目标格式的文件

### 8. ResizeImageAction — 调整图片大小

| 属性     | 值                         |
| -------- | -------------------------- |
| ID       | `action.resizeImage`       |
| 可见条件 | 选中项包含至少一个图片文件 |
| 菜单形式 | 子菜单（列出所有预设尺寸） |

**默认预设：**

| 选项                            | 说明                     |
| ------------------------------- | ------------------------ |
| 256px / 512px / 1024px / 2048px | 按宽度缩放               |
| 75% / 50% / 25%                 | 按百分比缩放             |
| 自定义…                         | 手动输入像素宽度或百分比 |

---

## 如何添加新动作

添加新动作只需 **3 步**，无需修改 Finder 扩展或设置界面的代码：

### Step 1: 创建 Action 文件

在 `iMouse/Core/Actions/` 目录下创建新文件，例如 `OpenInVSCodeAction.swift`：

```swift
import AppKit

struct OpenInVSCodeAction: ContextAction {

    let id = "action.openInVSCode"

    var displayName: String {
        NSLocalizedString("action.vscode.name", comment: "Open in VS Code")
    }

    var displayDescription: String {
        NSLocalizedString("action.vscode.desc", comment: "Open in Visual Studio Code")
    }

    let sfSymbolName = "chevron.left.forwardslash.chevron.right"

    func isVisible(for context: SelectionContext) -> Bool {
        context.kind != .none
    }

    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        .single(
            title: displayName,
            icon: NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil)
        )
    }

    func perform(context: SelectionContext, submenuId: String?) {
        guard let dir = context.effectiveDirectory else { return }

        // 使用 NSWorkspace 打开（沙盒友好）
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([dir], withApplicationAt: appURL, configuration: config)
        }
    }
}
```

### Step 2: 注册到 ActionRegistry

在 `Shared/ContextAction.swift` 的 `defaultActions` 数组中添加一行：

```swift
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
        OpenInVSCodeAction(),  // ← 新增
    ]
}
```

### Step 3: 添加翻译（可选但推荐）

`iMouse/Resources/en.lproj/Localizable.strings`：

```
"action.vscode.name" = "Open in VS Code";
"action.vscode.desc" = "Open selected files or folders in Visual Studio Code";
```

`iMouse/Resources/zh-Hans.lproj/Localizable.strings`：

```
"action.vscode.name" = "在 VS Code 中打开";
"action.vscode.desc" = "使用 Visual Studio Code 打开选中的文件或文件夹";
```

**就这样！** 重新构建后，新动作会自动出现在：

- Finder 右键菜单中
- 设置界面的动作列表中（带启用/禁用开关）

---

## 安全与权限

### 沙盒与权限说明

iMouse 采用**主 App 非沙盒 + FinderSync 扩展沙盒化**的架构（与 RClick 相同）：

**主 App（非沙盒）**：

| 权限                               | 用途                        |
| ---------------------------------- | --------------------------- |
| App Group `group.com.dogxi.iMouse` | 与扩展共享设置（JSON 文件） |

**FinderSync 扩展（沙盒化）**：

| 权限                                                | 用途                                     |
| --------------------------------------------------- | ---------------------------------------- |
| `com.apple.security.app-sandbox`                    | macOS 要求扩展必须沙盒化                 |
| `com.apple.security.files.user-selected.read-write` | 读写用户选择的文件（新建文件、转换图片） |
| `com.apple.security.files.downloads.read-write`     | 读写 Downloads 文件夹                    |
| App Group `group.com.dogxi.iMouse`                  | 读取主 App 写入的共享设置                |

> **为什么主 App 不启用沙盒？**
> 在非沙盒 App 中使用 `UserDefaults(suiteName:)` 会走 CFPreferences 的 `kCFPreferencesAnyUser` 路径，触发 `kTCCServiceSystemPolicyAppData` 的 TCC 授权弹窗。主 App 非沙盒化可以自由执行终端启动、AirDrop 等操作，扩展通过 URL scheme 委托给主 App。

### 终端启动安全

终端动作从扩展通过 URL scheme 委托给主 App 执行，主 App 使用 `NSWorkspace.shared.open` 通过 Launch Services 打开终端，不依赖 AppleScript 或 Automation 权限：

```swift
// ✅ 安全：扩展通过 URL scheme 委托给主 App
//    主 App 通过 Launch Services 打开，不拼接 shell 字符串
NSWorkspace.shared.open([dirURL], withApplicationAt: appURL, configuration: config)

// ❌ 危险：永远不要这样做
// system("open -a Ghostty '\(dirPath)'")
```

### App Group 与设置共享

主 App 和 Finder 扩展通过 App Group (`group.com.dogxi.iMouse`) 共享设置。
设置以 **JSON 文件**形式存储在 App Group 容器目录中，**不使用 `UserDefaults(suiteName:)`**：

```swift
// 主 App 和扩展都通过 JSON 文件读写设置
// 文件路径：App Group 容器 / com.dogxi.iMouse.settings.json
let settings = AppSettings.load()   // 从 JSON 文件加载
settings.save()                     // 写入 JSON 文件
```

---

## 调试指南

### 调试主 App

1. 在 Xcode 中选择 `iMouse` scheme，⌘R 运行
2. 应用出现在菜单栏，点击图标打开设置

### 调试 Finder Sync 扩展

1. 在 Xcode 中选择 `FinderSync` scheme
2. 点击运行，选择 `/System/Library/CoreServices/Finder.app` 作为宿主
3. Finder 重启后扩展加载，在 Finder 中右键文件触发断点

### 查看实时日志

```bash
# 实时查看 iMouse 的所有日志（主 App + 扩展）
log stream --predicate 'composedMessage CONTAINS "[iMouse"' --level debug

# 或按进程名过滤扩展日志
log stream --predicate 'process == "FinderSyncExt"' --level debug
```

### 强制重新加载扩展

```bash
pluginkit -e ignore -i com.dogxi.iMouse.FinderSync
pluginkit -e use -i com.dogxi.iMouse.FinderSync
killall Finder
```

### 检查扩展注册状态

```bash
pluginkit -m -v -i com.dogxi.iMouse.FinderSync
```

---

## 上传 GitHub

项目不包含任何敏感数据，可以直接上传：

- ✅ 无 API Key、密钥或 Token
- ✅ 无个人隐私数据
- ✅ `.gitignore` 已排除 `*.xcodeproj/`（由 XcodeGen 生成）、`build/`、`DerivedData/` 等构建产物
- ✅ 签名证书/Provisioning Profile 不包含在项目文件中
- ⚠️ `scripts/build.sh` 中硬编码了 Team ID（`NR23J92NS8`），上传前建议替换为占位符或从环境变量读取

**推荐步骤：**

```bash
cd /Users/dogxi/Git/iMouse
git init                          # 如果尚未初始化
git add .
git commit -m "feat: v1.1.0 — multi-terminal support via NSWorkspace.open"
git remote add origin https://github.com/<你的用户名>/iMouse.git
git push -u origin main
```

**注意：** `.gitignore` 已忽略 `*.xcodeproj/`，collaborators 克隆后需运行 `./setup.sh` 重新生成项目文件。

---

## 常见问题 (FAQ)

### Q: 右键菜单中没有出现 iMouse 的菜单项？

**A:** 检查以下几点：

1. Finder Sync 扩展是否已启用？
   ```bash
   pluginkit -m -i com.dogxi.iMouse.FinderSync
   ```
2. 尝试重启 Finder：`killall Finder`
3. 确认两个 target 的签名和 App Group 配置正确

### Q: 终端打不开？

**A:**

1. 在 iMouse 设置的「终端」标签页中，确认已选择正确的终端应用
2. 检查「安装状态」是否显示绿色 ✅
3. 如果显示未安装，点击「自动检测」或手动指定路径
4. 支持的终端：Ghostty、iTerm2、Terminal.app、Warp、Kitty、Alacritty 以及自定义

### Q: 设置修改后 Finder 扩展没有反映？

**A:** 两个 target 必须配置相同的 App Group: `group.com.dogxi.iMouse`。验证设置文件是否存在：

```bash
# 设置以 JSON 文件存储在 App Group 容器中（不使用 UserDefaults）
cat ~/Library/Group\ Containers/group.com.dogxi.iMouse/com.dogxi.iMouse.settings.json
```

### Q: 图片转换后质量不好？

**A:** 在设置的「图片」标签页中调整「有损压缩质量」滑块（默认 85%）。仅对 JPEG/HEIC/WebP 有效，PNG/TIFF/BMP 为无损格式不受影响。

### Q: WebP 格式转换支持吗？

**A:** 是的！macOS 14 Sonoma 及以上版本原生支持 WebP 读写（通过 ImageIO 框架）。

### Q: 如何修改 Bundle Identifier？

**A:** 需要同时修改以下位置：

1. `project.yml` 中两个 target 的 `PRODUCT_BUNDLE_IDENTIFIER`
2. `Shared/AppSettings.swift` 中的 `kAppGroupIdentifier` 常量
3. `iMouseApp.swift` 中 `pluginkit` 命令里的 bundle identifier
4. `Config/FinderSync.entitlements` 和 `Config/iMouse.entitlements` 中的 App Group

### Q: 如何发布/分发给其他人使用？

**A:** 两种方式：

1. **直接分发 .app**（Developer ID 签名）：Archive → Export → Developer ID Application，用户下载后放入 /Applications
2. **Mac App Store**：需要将主 App 也沙盒化，并使用 Security-Scoped Bookmarks 获取文件访问权限

---

## 更新日志

### v1.1.0

- ✅ **终端支持全面升级**：支持 Ghostty、iTerm2、Terminal.app、Warp、Kitty、Alacritty 及自定义终端
- ✅ **终端启动机制重构**：终端动作从扩展通过 `imouse://terminal` URL scheme 委托给主 App 执行，主 App 使用 `NSWorkspace.shared.open` 通过 Launch Services 打开，修复沙盒扩展中终端无法正确跳转到指定路径的问题
- ✅ **AirDrop 委托机制**：AirDrop 动作通过 `imouse://airdrop` URL scheme 委托给主 App 执行，解决 FinderSync 插件进程中 `NSSharingService.perform` 不受支持的问题
- ✅ **TCC 弹窗修复**：设置持久化从 `UserDefaults(suiteName:)` 改为 App Group 容器中的 JSON 文件，消除 `kTCCServiceSystemPolicyAppData` 授权弹窗
- ✅ **启动弹窗修复**：主 App 从 SwiftUI Scene 迁移为纯 AppKit（`NSStatusBar` + `NSMenu`），设置窗口按需创建，禁用 macOS 窗口恢复，启动时不再弹出任何窗口
- ✅ **FinderSync 右键菜单修复**：扩展监控目录改为根目录 `/`，修复沙盒容器路径导致 Finder 中右键菜单不显示的问题
- ✅ **菜单栏优化**：移除右键菜单中冗余的标题行和动作数量统计，界面更简洁
- ✅ **新增构建脚本** `scripts/build.sh`：一键构建 + 停止旧进程 + 安装到 /Applications + 重启

### v1.0.0

- 🎉 初始发布
- 8 个内置动作：新建文件、打开终端（Ghostty）、复制路径、复制名称、AirDrop、转换图片、调整图片大小
- 支持中英文双语
- 基于 XcodeGen + SwiftUI 构建

---

> **iMouse** — 让 Finder 右键菜单更强大 🖱️✨
