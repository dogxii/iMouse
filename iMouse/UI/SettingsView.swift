//
//  SettingsView.swift
//  iMouse
//
//  主设置界面 —— 使用 TabView 分为多个标签页：
//  1. 「通用」：动作列表，启用/禁用开关，语言设置，图标显示开关
//  2. 「新建文件」：文件模板和默认扩展名配置
//  3. 「复制」：路径分隔符、名称模式配置
//  4. 「图片」：转换格式、缩放选项、质量配置
//  5. 「终端」：终端应用选择和路径配置
//  6. 「关于」：版本信息、扩展状态和 GitHub 链接
//

import SwiftUI

// MARK: - SettingsView（设置主视图）

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.general", comment: "通用"),
                        systemImage: "gearshape"
                    )
                }

            NewFileTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.newFile", comment: "新建文件"),
                        systemImage: "doc.badge.plus"
                    )
                }

            CopyTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.copy", comment: "复制"),
                        systemImage: "doc.on.clipboard"
                    )
                }

            ImageTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.image", comment: "图片"),
                        systemImage: "photo"
                    )
                }

            TerminalTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.terminal", comment: "终端"),
                        systemImage: "terminal"
                    )
                }

            AboutTab()
                .tabItem {
                    Label(
                        NSLocalizedString("settings.tab.about", comment: "关于"),
                        systemImage: "info.circle"
                    )
                }
        }
        .environmentObject(settingsManager)
        .frame(width: 580, height: 500)
    }
}

// MARK: - GeneralTab（通用标签页）

/// 显示所有已注册动作的列表，每个动作可以单独启用/禁用。
/// 还包含语言设置和菜单图标显示开关。
struct GeneralTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showRestartHint = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── 外观与语言设置 ──
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    // 语言设置
                    HStack {
                        Label(
                            NSLocalizedString("settings.general.language", comment: "Language"),
                            systemImage: "globe"
                        )

                        Spacer()

                        Picker("", selection: $settingsManager.settings.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .onChange(of: settingsManager.settings.language) { _, _ in
                            showRestartHint = true
                        }
                    }

                    if showRestartHint {
                        Text(NSLocalizedString("settings.general.restartHint", comment: "Language change will take full effect after restarting the app."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Divider()

                    // 菜单图标开关
                    HStack {
                        Label(
                            NSLocalizedString("settings.general.showIcons", comment: "Show icons in context menu"),
                            systemImage: "photo.on.rectangle"
                        )

                        Spacer()

                        Toggle("", isOn: $settingsManager.settings.showMenuIcons)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                .padding(6)
            }

            // ── 动作列表标题 ──
            Text(NSLocalizedString("settings.general.title", comment: "右键菜单动作"))
                .font(.headline)

            Text(NSLocalizedString("settings.general.subtitle", comment: "选择在 Finder 右键菜单中显示哪些动作。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 动作列表
            List {
                ForEach(ActionRegistry.shared.actions, id: \.id) { action in
                    ActionRow(action: action)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            // 底部操作栏
            HStack {
                Button(NSLocalizedString("settings.general.enableAll", comment: "全部启用")) {
                    for action in ActionRegistry.shared.actions {
                        settingsManager.settings.setActionEnabled(action.id, enabled: true)
                    }
                }

                Button(NSLocalizedString("settings.general.disableAll", comment: "全部禁用")) {
                    for action in ActionRegistry.shared.actions {
                        settingsManager.settings.setActionEnabled(action.id, enabled: false)
                    }
                }

                Spacer()

                Button(NSLocalizedString("settings.general.resetDefaults", comment: "恢复默认")) {
                    settingsManager.resetToDefaults()
                }
            }
        }
        .padding(20)
    }
}

// MARK: - ActionRow（单个动作行）

/// 列表中的单个动作行：图标 + 名称 + 描述 + 启用开关
struct ActionRow: View {
    let action: ContextAction
    @EnvironmentObject var settingsManager: SettingsManager

    /// 通过 Binding 双向绑定启用状态
    private var isEnabled: Binding<Bool> {
        Binding(
            get: { settingsManager.settings.isActionEnabled(action.id) },
            set: { newValue in settingsManager.settings.setActionEnabled(action.id, enabled: newValue) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // SF Symbol 图标
            Image(systemName: action.sfSymbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            // 名称和描述
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(action.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // 启用/禁用开关
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - NewFileTab（新建文件配置）

struct NewFileTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var newTemplateExt: String = ""
    @State private var newTemplateName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("settings.newFile.title", comment: "新建文件设置"))
                .font(.headline)

            // 默认扩展名
            HStack {
                Text(NSLocalizedString("settings.newFile.defaultExt", comment: "默认文件扩展名:"))
                TextField("txt", text: $settingsManager.settings.defaultNewFileExtension)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // 文件模板列表
            Text(NSLocalizedString("settings.newFile.templates", comment: "文件模板（出现在子菜单中）"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(settingsManager.settings.newFileTemplates.enumerated()), id: \.offset) { index, template in
                    HStack {
                        Text(template.displayName)
                            .frame(width: 120, alignment: .leading)
                        Text(".\(template.extension_)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            settingsManager.settings.newFileTemplates.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { indices, newOffset in
                    settingsManager.settings.newFileTemplates.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            // 添加新模板
            HStack {
                TextField(
                    NSLocalizedString("settings.newFile.addName", comment: "显示名称"),
                    text: $newTemplateName
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

                TextField(
                    NSLocalizedString("settings.newFile.addExt", comment: "扩展名"),
                    text: $newTemplateExt
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Button(NSLocalizedString("settings.newFile.add", comment: "添加")) {
                    let ext = newTemplateExt.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: ".", with: "")
                    let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !ext.isEmpty, !name.isEmpty else { return }

                    let template = NewFileTemplate(extension_: ext, displayName: name)
                    settingsManager.settings.newFileTemplates.append(template)
                    newTemplateExt = ""
                    newTemplateName = ""
                }
                .disabled(newTemplateExt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button(NSLocalizedString("settings.newFile.resetTemplates", comment: "恢复默认模板")) {
                    settingsManager.settings.newFileTemplates = AppSettings.defaultNewFileTemplates
                }
                .font(.caption)
            }
        }
        .padding(20)
    }
}

// MARK: - CopyTab（复制相关配置）

struct CopyTab: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── 复制路径设置 ──
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        NSLocalizedString("settings.copy.pathSection", comment: "复制路径"),
                        systemImage: "doc.on.clipboard"
                    )
                    .font(.headline)

                    HStack {
                        Text(NSLocalizedString("settings.copy.separator", comment: "多文件路径分隔符:"))
                        Picker("", selection: $settingsManager.settings.pathSeparator) {
                            ForEach(PathSeparator.allCases) { sep in
                                Text(sep.displayName).tag(sep)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    // 预览效果
                    Text(NSLocalizedString("settings.copy.preview", comment: "预览:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(previewPaths())
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
                .padding(8)
            }

            // ── 复制名称设置 ──
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        NSLocalizedString("settings.copy.nameSection", comment: "复制名称"),
                        systemImage: "textformat"
                    )
                    .font(.headline)

                    Picker(
                        NSLocalizedString("settings.copy.nameMode", comment: "名称格式:"),
                        selection: $settingsManager.settings.copyNameMode
                    ) {
                        ForEach(CopyNameMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    // 示例说明
                    let example = settingsManager.settings.copyNameMode == .withExtension
                        ? "photo.png"
                        : "photo"
                    Text(String(
                        format: NSLocalizedString("settings.copy.nameExample", comment: "示例: %@"),
                        example
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
    }

    /// 生成路径预览文本
    private func previewPaths() -> String {
        let sep = settingsManager.settings.pathSeparator.character
        return ["/Users/me/Documents/file1.txt",
                "/Users/me/Documents/file2.txt"]
            .joined(separator: sep)
    }
}

// MARK: - ImageTab（图片相关配置）

struct ImageTab: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── 图片转换格式 ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            NSLocalizedString("settings.image.convertSection", comment: "转换图片格式"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.headline)

                        Text(NSLocalizedString("settings.image.convertDesc", comment: "选择在「转换为」子菜单中显示的格式。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // 格式启用开关网格
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(ImageFormat.allCases) { format in
                                let isEnabled = settingsManager.settings.enabledImageFormats.contains(format)
                                Toggle(format.displayName, isOn: Binding(
                                    get: { isEnabled },
                                    set: { newValue in
                                        if newValue {
                                            if !settingsManager.settings.enabledImageFormats.contains(format) {
                                                settingsManager.settings.enabledImageFormats.append(format)
                                            }
                                        } else {
                                            settingsManager.settings.enabledImageFormats.removeAll { $0 == format }
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }

                        Divider()

                        // 图片质量滑块
                        HStack {
                            Text(NSLocalizedString("settings.image.quality", comment: "有损压缩质量:"))
                            Slider(
                                value: $settingsManager.settings.imageConversionQuality,
                                in: 0.1...1.0,
                                step: 0.05
                            )
                            Text("\(Int(settingsManager.settings.imageConversionQuality * 100))%")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 44, alignment: .trailing)
                        }

                        Text(NSLocalizedString("settings.image.qualityHint", comment: "仅对 JPEG、HEIC、WebP 等有损格式生效。"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                }

                // ── 图片缩放选项 ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            NSLocalizedString("settings.image.resizeSection", comment: "调整图片大小"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.headline)

                        Text(NSLocalizedString("settings.image.resizeDesc", comment: "在「调整大小」子菜单中显示的预设选项。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // 列表头部
                        HStack(spacing: 0) {
                            Text("菜单名称")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text("类型")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Text("宽 (px)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text("高 (px) / %")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 72, alignment: .leading)
                        }
                        .padding(.horizontal, 6)

                        // 可编辑列表
                        List {
                            ForEach($settingsManager.settings.resizeOptions) { $option in
                                ResizeOptionRow(option: $option) {
                                    settingsManager.settings.resizeOptions.removeAll { $0.id == option.id }
                                }
                            }
                            .onMove { indices, newOffset in
                                settingsManager.settings.resizeOptions.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))
                        .frame(height: 180)

                        HStack(spacing: 8) {
                            // 新增尺寸
                            Button {
                                let newOption = ImageResizeOption(
                                    label: "新尺寸",
                                    kind: .dimensions(width: 800, height: 600)
                                )
                                settingsManager.settings.resizeOptions.append(newOption)
                            } label: {
                                Label("添加尺寸", systemImage: "plus")
                            }
                            .font(.caption)

                            // 新增百分比
                            Button {
                                let newOption = ImageResizeOption(
                                    label: "新比例",
                                    kind: .percentage(80)
                                )
                                settingsManager.settings.resizeOptions.append(newOption)
                            } label: {
                                Label("添加百分比", systemImage: "percent")
                            }
                            .font(.caption)

                            Spacer()

                            Button(NSLocalizedString("settings.image.resetResize", comment: "恢复默认")) {
                                settingsManager.settings.resizeOptions = AppSettings.defaultResizeOptions
                            }
                            .font(.caption)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - ResizeOptionRow（单行可编辑组件）

/// 图片缩放预设的单行编辑 UI
/// 支持三种类型：dimensions（宽×高）、percentage（百分比）、width（仅宽度）
private struct ResizeOptionRow: View {
    @Binding var option: ImageResizeOption
    let onDelete: () -> Void

    // 从 kind 派生的临时编辑状态
    @State private var widthText: String = ""
    @State private var heightOrPctText: String = ""
    @State private var selectedType: ResizeType = .dimensions

    enum ResizeType: String, CaseIterable {
        case dimensions = "宽 × 高"
        case percentage = "百分比"
        case widthOnly  = "仅宽度"
    }

    var body: some View {
        HStack(spacing: 6) {
            // 菜单名称（可编辑）
            TextField("名称", text: $option.label)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 104)

            // 类型选择
            Picker("", selection: $selectedType) {
                ForEach(ResizeType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .labelsHidden()
            .frame(width: 84)
            .onChange(of: selectedType) { _, newType in
                applyTypeChange(newType)
            }

            // 宽度输入
            TextField(selectedType == .percentage ? "—" : "宽", text: $widthText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 66)
                .disabled(selectedType == .percentage)
                .foregroundStyle(selectedType == .percentage ? .secondary : .primary)
                .onChange(of: widthText) { _, _ in commitEdits() }

            // 高度 / 百分比输入
            TextField(selectedType == .percentage ? "%" : "高", text: $heightOrPctText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 66)
                .disabled(selectedType == .widthOnly)
                .foregroundStyle(selectedType == .widthOnly ? .secondary : .primary)
                .onChange(of: heightOrPctText) { _, _ in commitEdits() }

            Spacer()

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .onAppear { loadFromKind() }
    }

    // MARK: - 内部方法

    /// 从 option.kind 初始化编辑状态
    private func loadFromKind() {
        switch option.kind {
        case .dimensions(let w, let h):
            selectedType = .dimensions
            widthText = "\(w)"
            heightOrPctText = "\(h)"
        case .percentage(let pct):
            selectedType = .percentage
            widthText = ""
            heightOrPctText = "\(pct)"
        case .width(let w):
            selectedType = .widthOnly
            widthText = "\(w)"
            heightOrPctText = ""
        }
    }

    /// 类型切换时设置合理默认值
    private func applyTypeChange(_ newType: ResizeType) {
        switch newType {
        case .dimensions:
            let w = Int(widthText) ?? 800
            let h = Int(heightOrPctText) ?? w
            widthText = "\(w)"
            heightOrPctText = "\(h)"
            option.kind = .dimensions(width: w, height: h)
        case .percentage:
            let pct = Int(heightOrPctText) ?? 50
            widthText = ""
            heightOrPctText = "\(pct)"
            option.kind = .percentage(pct)
        case .widthOnly:
            let w = Int(widthText) ?? 800
            widthText = "\(w)"
            heightOrPctText = ""
            option.kind = .width(w)
        }
    }

    /// 将文本框内容写回 option.kind
    private func commitEdits() {
        switch selectedType {
        case .dimensions:
            let w = max(1, Int(widthText) ?? 0)
            let h = max(1, Int(heightOrPctText) ?? 0)
            if w > 0 && h > 0 {
                option.kind = .dimensions(width: w, height: h)
            }
        case .percentage:
            let pct = max(1, min(1000, Int(heightOrPctText) ?? 0))
            if pct > 0 {
                option.kind = .percentage(pct)
            }
        case .widthOnly:
            let w = max(1, Int(widthText) ?? 0)
            if w > 0 {
                option.kind = .width(w)
            }
        }
    }
}

// MARK: - TerminalTab（终端配置）

struct TerminalTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var detectedPath: String = ""
    @State private var isDetecting: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── 终端应用选择 ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            NSLocalizedString("settings.terminal.appSection", comment: "Terminal Application"),
                            systemImage: "terminal"
                        )
                        .font(.headline)

                        Text(NSLocalizedString("settings.terminal.appDesc", comment: "Choose which terminal application to use when opening a terminal from Finder."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // 终端应用选择器
                        Picker(
                            NSLocalizedString("settings.terminal.appPicker", comment: "Terminal:"),
                            selection: $settingsManager.settings.terminalApp
                        ) {
                            ForEach(TerminalApp.allCases) { app in
                                HStack {
                                    Text(app.displayName)
                                }
                                .tag(app)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: settingsManager.settings.terminalApp) { _, newApp in
                            // 切换终端类型时，清空自定义路径，让用户重新配置或自动检测
                            settingsManager.settings.terminalCustomPath = ""
                            detectedPath = ""
                        }

                        // 安装状态指示
                        let currentApp = settingsManager.settings.terminalApp
                        if currentApp != .custom {
                            HStack(spacing: 4) {
                                if isTerminalInstalled(currentApp) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(String(
                                        format: NSLocalizedString("settings.terminal.installed", comment: "%@ is installed"),
                                        currentApp.displayName
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(String(
                                        format: NSLocalizedString("settings.terminal.notInstalled", comment: "%@ is not installed"),
                                        currentApp.displayName
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                // ── 自定义路径配置 ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            NSLocalizedString("settings.terminal.pathSection", comment: "Custom Path"),
                            systemImage: "folder"
                        )
                        .font(.headline)

                        if settingsManager.settings.terminalApp == .custom {
                            Text(NSLocalizedString("settings.terminal.customPathRequired", comment: "Specify the path to your terminal application (.app bundle or executable)."))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text(NSLocalizedString("settings.terminal.customPathOptional", comment: "Optionally override the auto-detected path. Leave empty for auto-detection."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(NSLocalizedString("settings.terminal.path", comment: "路径:"))

                            TextField(
                                NSLocalizedString("settings.terminal.placeholder", comment: "自动检测"),
                                text: $settingsManager.settings.terminalCustomPath
                            )
                            .textFieldStyle(.roundedBorder)

                            // 浏览按钮
                            Button(NSLocalizedString("settings.terminal.browse", comment: "浏览…")) {
                                browseForTerminal()
                            }
                        }

                        // 自动检测按钮
                        HStack {
                            Button {
                                detectTerminalPath()
                            } label: {
                                Label(
                                    NSLocalizedString("settings.terminal.detect", comment: "自动检测"),
                                    systemImage: "magnifyingglass"
                                )
                            }
                            .disabled(isDetecting || settingsManager.settings.terminalApp == .custom)

                            if isDetecting {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if !detectedPath.isEmpty {
                                Text(detectedPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(detectedPath.contains("✅") ? .green : .red)
                            }
                        }

                        // 搜索路径提示
                        if settingsManager.settings.terminalApp != .custom {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("settings.terminal.searchPaths", comment: "自动检测时搜索的路径:"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(settingsManager.settings.terminalApp.defaultSearchPaths, id: \.self) { path in
                                        Text("• \(path)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text("• PATH " + NSLocalizedString("settings.terminal.envVar", comment: "environment variable"))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                // ── 终端行为说明 ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            NSLocalizedString("settings.terminal.behaviorSection", comment: "Behavior"),
                            systemImage: "info.circle"
                        )
                        .font(.headline)

                        Text(NSLocalizedString("settings.terminal.behaviorDesc", comment: "Right-clicking in Finder will show two options: \"New Window Here\" opens a new terminal window, and \"New Tab Here\" opens a new tab in the existing terminal window. Both will navigate to the selected directory."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if settingsManager.settings.terminalApp == .alacritty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text(NSLocalizedString("settings.terminal.alacrittyNote", comment: "Note: Alacritty does not support tabs natively. \"New Tab Here\" will open a new window instead."))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    /// 检查终端应用是否已安装
    private func isTerminalInstalled(_ terminal: TerminalApp) -> Bool {
        if let bundleId = terminal.bundleIdentifier {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                return true
            }
        }
        // 检查默认路径
        let fm = FileManager.default
        for path in terminal.defaultSearchPaths {
            if path.hasSuffix(".app") {
                if fm.fileExists(atPath: path) {
                    return true
                }
            } else {
                if fm.isExecutableFile(atPath: path) {
                    return true
                }
            }
        }
        return false
    }

    /// 弹出文件选择对话框，让用户手动选择终端
    private func browseForTerminal() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("settings.terminal.browseTitle", comment: "Select terminal application or executable")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application, .unixExecutable]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.settings.terminalCustomPath = url.path(percentEncoded: false)
        }
    }

    /// 自动检测终端的安装路径
    private func detectTerminalPath() {
        isDetecting = true
        detectedPath = ""

        let terminal = settingsManager.settings.terminalApp

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var found: String? = nil

            for path in terminal.defaultSearchPaths {
                if path.hasSuffix(".app") {
                    if fm.fileExists(atPath: path) {
                        found = path
                        break
                    }
                } else if fm.isExecutableFile(atPath: path) {
                    found = path
                    break
                }
            }

            // 如果常见路径都找不到，尝试通过 NSWorkspace 查找 bundle identifier
            // 不使用 Process() / shell 命令，因为沙盒环境下会触发 TCC 弹窗
            if found == nil, let bundleId = terminal.bundleIdentifier {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    found = appURL.path(percentEncoded: false)
                }
            }

            // 额外检查 Homebrew 路径（沙盒内 FileManager 可以检查文件是否存在）
            if found == nil {
                let extraPaths: [String]
                switch terminal {
                case .ghostty:   extraPaths = ["/opt/homebrew/bin/ghostty", "/usr/local/bin/ghostty"]
                case .kitty:     extraPaths = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"]
                case .alacritty: extraPaths = ["/opt/homebrew/bin/alacritty", "/usr/local/bin/alacritty"]
                default:         extraPaths = []
                }
                for path in extraPaths {
                    if fm.isExecutableFile(atPath: path) {
                        found = path
                        break
                    }
                }
            }

            DispatchQueue.main.async {
                isDetecting = false
                if let found {
                    detectedPath = "✅ \(found)"
                    settingsManager.settings.terminalCustomPath = found
                } else {
                    detectedPath = String(
                        format: NSLocalizedString("settings.terminal.notFound", comment: "❌ %@ not found"),
                        terminal.displayName
                    )
                }
            }
        }
    }
}

// MARK: - AboutTab（关于标签页）

struct AboutTab: View {
    @State private var extensionStatus: String = "..."

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App 图标和名称
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            } else {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
            }

            Text("iMouse")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Super Right Click for Finder")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("about.version", comment: "版本 1.0.0"))
                .font(.caption)
                .foregroundStyle(.tertiary)

            // GitHub 链接
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption)
                Link("GitHub: dogxii/iMouse", destination: URL(string: "https://github.com/dogxii/iMouse")!)
                    .font(.caption)
            }
            .foregroundStyle(.blue)

            Divider()
                .frame(width: 300)

            // Finder 扩展状态
            GroupBox {
                VStack(spacing: 8) {
                    Label(
                        NSLocalizedString("about.extensionStatus", comment: "Finder 扩展状态"),
                        systemImage: "puzzlepiece.extension"
                    )
                    .font(.headline)

                    Text(extensionStatus)
                        .font(.callout)
                        .foregroundStyle(extensionStatus.contains("✅") ? .green : .orange)

                    Button(NSLocalizedString("about.openExtensionSettings", comment: "打开扩展设置")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
                .padding(8)
            }
            .frame(width: 360)

            Spacer()

            // 版权信息
            VStack(spacing: 2) {
                Text("© 2026 dogxi. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text("Made with ❤️ for macOS")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(20)
        .onAppear {
            checkExtensionStatus()
        }
    }

    /// 检查 Finder Sync 扩展是否已启用
    ///
    /// ── 重要 ──
    /// 不使用 Process()+pluginkit 检测，因为 Process() 运行外部二进制会触发
    /// kTCCServiceDeveloperTool / kTCCServiceSystemPolicyAppData TCC 检查，
    /// 导致 macOS 弹出 "iMouse would like to access data from other apps" 对话框。
    /// 也不使用 NSAppleScript，同样会触发 TCC。
    ///
    /// 只通过检查 appex bundle 是否存在于 PlugIns 目录来判断扩展状态。
    private func checkExtensionStatus() {
        extensionStatus = NSLocalizedString("about.checking", comment: "正在检查…")

        // 检查 appex bundle 是否存在于 PlugIns 目录
        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let appexURL = pluginsURL.appendingPathComponent("FinderSyncExt.appex")
            let appexExists = FileManager.default.fileExists(atPath: appexURL.path)

            if appexExists {
                extensionStatus = NSLocalizedString("about.extensionEnabled", comment: "✅ 扩展已启用")
            } else {
                extensionStatus = NSLocalizedString("about.extensionDisabled", comment: "❌ 扩展未启用 — 请在系统设置中启用")
            }
        } else {
            extensionStatus = NSLocalizedString("about.extensionUnknown", comment: "⚠️ 无法检测扩展状态")
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
}
