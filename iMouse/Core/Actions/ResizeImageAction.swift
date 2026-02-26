//
//  ResizeImageAction.swift
//  iMouse
//
//  「调整图片大小」动作：按预设尺寸（宽度像素值或百分比）缩放选中的图片文件。
//  始终保持原始宽高比，使用 CoreGraphics 进行高质量缩放。
//
//  缩放后的文件保存在原文件旁边，命名规则：
//  - 按宽度缩放: photo_512w.jpg
//  - 按百分比缩放: photo_50pct.jpg
//  - 按指定尺寸: photo_800x600.jpg
//  - 如果同名文件已存在: photo_512w 2.jpg、photo_512w 3.jpg、…
//
//  ── 自定义尺寸对话框 ──
//  FinderSync 扩展中 NSAlert 的 accessoryView 无法可靠地获取键盘焦点，
//  因为扩展进程不是前台应用，macOS 不会将键盘事件路由给它。
//  解决方案：使用独立的 NSWindow（浮动窗口）替代 NSAlert + NSPanel，
//  手动将窗口设为 key window 并强制激活进程，确保 NSTextField 能接收键盘输入。
//
//  新版自定义对话框支持三种模式：
//  1. 仅宽度（保持宽高比）
//  2. 仅高度（保持宽高比）
//  3. 宽度 × 高度（精确尺寸，可能改变宽高比）
//  4. 百分比（等比缩放）
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ResizeImageAction: ContextAction {

    // MARK: - 标识

    let id = "action.resizeImage"

    var displayName: String {
        NSLocalizedString("action.resize.name", comment: "调整图片大小")
    }

    var displayDescription: String {
        NSLocalizedString("action.resize.desc", comment: "按预设尺寸缩放选中的图片，保持宽高比")
    }

    let sfSymbolName = "arrow.up.left.and.arrow.down.right"

    // MARK: - 可见性

    /// 「调整图片大小」仅在选中的文件中包含至少一个图片文件时显示。
    func isVisible(for context: SelectionContext) -> Bool {
        return context.hasImages
    }

    // MARK: - 菜单表示

    /// 显示为子菜单，列出所有预设的缩放选项 + 自定义尺寸选项供用户选择。
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        let settings = AppSettings.load()
        let options = settings.resizeOptions

        var children: [(id: String, title: String, icon: NSImage?)] = options.map { option in
            (
                id: option.label,
                title: option.label,
                icon: nil
            )
        }

        // 添加自定义尺寸选项
        children.append((
            id: "__custom__",
            title: NSLocalizedString("action.resize.custom", comment: "Custom Size…"),
            icon: NSImage(systemSymbolName: "pencil.and.ruler", accessibilityDescription: nil)
        ))

        return .submenu(
            title: displayName,
            icon: NSImage(systemSymbolName: sfSymbolName, accessibilityDescription: nil),
            children: children
        )
    }

    // MARK: - 执行

    func perform(context: SelectionContext, submenuId: String?) {
        guard let optionLabel = submenuId else { return }

        let settings = AppSettings.load()

        let option: ImageResizeOption

        if optionLabel == "__custom__" {
            // 弹出自定义尺寸输入对话框
            // Must run on main thread and activate our process to bring panel to front
            var customOption: ImageResizeOption?
            if Thread.isMainThread {
                customOption = promptForCustomSize()
            } else {
                DispatchQueue.main.sync {
                    customOption = promptForCustomSize()
                }
            }
            guard let customOption else {
                return // 用户取消
            }
            option = customOption
        } else {
            // 通过 label 找到对应的缩放选项
            guard let found = settings.resizeOptions.first(where: { $0.label == optionLabel }) else {
                return
            }
            option = found
        }

        // 只处理图片文件
        let imageItems = context.imageFiles
        guard !imageItems.isEmpty else { return }

        // 在后台线程执行缩放（可能耗时较长）
        DispatchQueue.global(qos: .userInitiated).async {
            var failedFiles: [String] = []

            for item in imageItems {
                let success = self.resizeImage(
                    sourceURL: item.url,
                    baseName: item.nameWithoutExtension,
                    originalExtension: item.pathExtension,
                    option: option,
                    quality: settings.imageConversionQuality
                )

                if !success {
                    failedFiles.append(item.name)
                }
            }

            // 如果有缩放失败的文件，在主线程上显示提示
            if !failedFiles.isEmpty {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: NSLocalizedString("action.resize.error.title", comment: "缩放失败"),
                        message: String(
                            format: NSLocalizedString(
                                "action.resize.error.someFailed",
                                comment: "以下文件缩放失败:\n%@"
                            ),
                            failedFiles.joined(separator: "\n")
                        )
                    )
                }
            }
        }
    }

    // MARK: - 核心缩放逻辑

    /// 缩放单个图片文件并保存。
    ///
    /// - Parameters:
    ///   - sourceURL: 原始图片文件的 URL
    ///   - baseName: 原始文件的基础名称（不含扩展名）
    ///   - originalExtension: 原始文件的扩展名（例如 "jpg"）
    ///   - option: 缩放选项（目标宽度、百分比或精确尺寸）
    ///   - quality: 图片质量（0.0 ~ 1.0），对有损格式如 JPEG/HEIC 生效
    /// - Returns: 是否成功
    private func resizeImage(
        sourceURL: URL,
        baseName: String,
        originalExtension: String,
        option: ImageResizeOption,
        quality: Double
    ) -> Bool {

        // 1. 读取源图片
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return false
        }

        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)

        // 防止除以零
        guard originalWidth > 0 && originalHeight > 0 else { return false }

        let aspectRatio = originalHeight / originalWidth

        // 2. 根据缩放选项计算目标尺寸
        let targetWidth: CGFloat
        let targetHeight: CGFloat

        switch option.kind {
        case .width(let w):
            targetWidth = CGFloat(w)
            targetHeight = round(targetWidth * aspectRatio)
        case .percentage(let pct):
            let scale = CGFloat(pct) / 100.0
            targetWidth = round(originalWidth * scale)
            targetHeight = round(originalHeight * scale)
        case .dimensions(let w, let h):
            targetWidth = CGFloat(w)
            targetHeight = CGFloat(h)
        }

        // 确保目标尺寸至少为 1x1
        let finalWidth = max(1, Int(targetWidth))
        let finalHeight = max(1, Int(targetHeight))

        // 如果目标尺寸与原始尺寸相同，跳过（没有意义）
        if finalWidth == Int(originalWidth) && finalHeight == Int(originalHeight) {
            return true
        }

        // 3. 使用 CoreGraphics 创建缩放后的图片
        //    CGContext 提供高质量的双线性/Lanczos 插值
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return false
        }

        // 保留 alpha 通道信息
        let bitmapInfo = cgImage.bitmapInfo
        let alphaInfo = bitmapInfo.intersection(.alphaInfoMask)

        // 如果原图没有 alpha 通道，就不强制添加
        let contextBitmapInfo: UInt32
        if alphaInfo == CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue) ||
           alphaInfo == CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue) ||
           alphaInfo == CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            contextBitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        } else {
            contextBitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        }

        guard let context = CGContext(
            data: nil,
            width: finalWidth,
            height: finalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: contextBitmapInfo
        ) else {
            return false
        }

        // 设置高质量插值
        context.interpolationQuality = .high

        // 在目标尺寸的矩形中绘制原图（CoreGraphics 自动缩放）
        let drawRect = CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight)
        context.draw(cgImage, in: drawRect)

        // 从 context 中提取缩放后的 CGImage
        guard let resizedImage = context.makeImage() else {
            return false
        }

        // 4. 确定输出文件路径
        let suffix = suffixForOption(option)
        let destURL = uniqueOutputURL(
            sourceURL: sourceURL,
            baseName: baseName,
            suffix: suffix,
            targetExtension: originalExtension  // 保持原始格式
        )

        // 5. 保存缩放后的图片（使用 ImageIO，保持原始格式）
        guard let uti = UTType(filenameExtension: originalExtension)?.identifier else {
            return false
        }

        guard let imageDestination = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            uti as CFString,
            1,
            nil
        ) else {
            return false
        }

        // 设置输出参数
        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        // 更新 DPI 元数据以反映新尺寸
        options[kCGImagePropertyDPIWidth] = 72.0
        options[kCGImagePropertyDPIHeight] = 72.0

        // 更新像素尺寸元数据
        options[kCGImagePropertyPixelWidth] = finalWidth
        options[kCGImagePropertyPixelHeight] = finalHeight

        CGImageDestinationAddImage(imageDestination, resizedImage, options as CFDictionary)

        return CGImageDestinationFinalize(imageDestination)
    }

    // MARK: - 辅助方法

    /// 根据缩放选项生成文件名后缀。
    ///
    /// - Parameter option: 缩放选项
    /// - Returns: 后缀字符串，例如 "_512w"、"_50pct" 或 "_800x600"
    private func suffixForOption(_ option: ImageResizeOption) -> String {
        switch option.kind {
        case .width(let w):
            return "_\(w)w"
        case .percentage(let pct):
            return "_\(pct)pct"
        case .dimensions(let w, let h):
            return "_\(w)x\(h)"
        }
    }

    /// 生成不冲突的输出文件 URL。
    ///
    /// 规则：
    /// 1. 先尝试带后缀的名称: photo_512w.jpg
    /// 2. 如果已存在，加编号: photo_512w 2.jpg、photo_512w 3.jpg、…
    ///
    /// - Parameters:
    ///   - sourceURL: 原始文件的 URL
    ///   - baseName: 原始文件的基础名称（不含扩展名）
    ///   - suffix: 缩放后缀（例如 "_512w"）
    ///   - targetExtension: 目标文件扩展名
    /// - Returns: 一个在同目录下不存在的文件 URL
    private func uniqueOutputURL(
        sourceURL: URL,
        baseName: String,
        suffix: String,
        targetExtension: String
    ) -> URL {
        let parentDir = sourceURL.deletingLastPathComponent()
        let fm = FileManager.default
        let outputBaseName = "\(baseName)\(suffix)"

        // 第一次尝试
        let firstAttempt = parentDir.appendingPathComponent("\(outputBaseName).\(targetExtension)")
        if !fm.fileExists(atPath: firstAttempt.path(percentEncoded: false)) {
            return firstAttempt
        }

        // 编号递增
        var counter = 2
        while counter <= 10000 {
            let candidate = parentDir.appendingPathComponent(
                "\(outputBaseName) \(counter).\(targetExtension)"
            )
            if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            counter += 1
        }

        // 后备方案：使用时间戳
        let timestamp = Int(Date().timeIntervalSince1970)
        return parentDir.appendingPathComponent(
            "\(baseName)_resized_\(timestamp).\(targetExtension)"
        )
    }

    // MARK: - 自定义尺寸对话框

    /// 弹出自定义尺寸输入面板，让用户输入目标尺寸。
    ///
    /// 支持以下输入模式：
    /// - 宽度（像素）：保持宽高比
    /// - 高度（像素）：保持宽高比
    /// - 宽度 × 高度（像素）：精确尺寸
    /// - 百分比：等比缩放
    ///
    /// 使用独立的 NSWindow 替代 NSAlert / NSPanel，因为：
    /// - FinderSync 扩展中 NSAlert 的 accessoryView (NSTextField) 无法获取键盘焦点
    /// - NSWindow 可以通过 canBecomeKey override 和 makeKeyAndOrderFront
    ///   强制获取键盘焦点
    /// - 通过 NSApp.activate(ignoringOtherApps:) 将扩展进程提升为前台进程
    ///
    /// - Returns: 用户输入的缩放选项，如果用户取消则返回 nil
    private func promptForCustomSize() -> ImageResizeOption? {
        var result: ImageResizeOption?

        let panel = CustomSizeWindow { option in
            result = option
        }
        panel.showAndRun()

        return result
    }

    /// 显示错误提示对话框
    private func showAlert(title: String, message: String) {
        let showBlock = {
            // Activate our process so the alert is visible
            NSApp?.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
            alert.window.level = .floating
            alert.runModal()
        }

        if Thread.isMainThread {
            showBlock()
        } else {
            DispatchQueue.main.async {
                showBlock()
            }
        }
    }
}


// MARK: - CustomSizeWindow（自定义尺寸输入窗口）

/// 独立的浮动窗口，用于在 FinderSync 扩展上下文中可靠地接收键盘输入。
///
/// 使用 NSWindow（而非 NSPanel）以获得更可靠的键盘焦点控制。
///
/// 设计要点：
/// 1. 使用 NSWindow 子类并覆盖 canBecomeKey/canBecomeMain → true
/// 2. 设置 level = .floating 确保窗口在最前
/// 3. 调用 NSApp.activate(ignoringOtherApps:) 将进程提升为前台
/// 4. 多次调用 makeFirstResponder 确保输入框获得焦点
/// 5. 使用 NSApp.runModal(for:) 阻塞等待用户输入
///
/// 支持三种模式通过分段控制切换：
/// - 宽度模式：输入宽度像素值，保持宽高比
/// - 尺寸模式：同时输入宽度和高度像素值
/// - 百分比模式：输入百分比，等比缩放
private class CustomSizeWindow: NSWindow {

    /// 模式枚举
    private enum ResizeMode: Int {
        case width = 0
        case dimensions = 1
        case percentage = 2
    }

    private let widthField: NSTextField
    private let heightField: NSTextField
    private let percentField: NSTextField
    private let errorLabel: NSTextField
    private let modeSegment: NSSegmentedControl
    private let widthRow: NSView
    private let heightRow: NSView
    private let percentRow: NSView
    private var onComplete: ((ImageResizeOption?) -> Void)?

    init(onComplete: @escaping (ImageResizeOption?) -> Void) {
        self.onComplete = onComplete

        // ── 创建输入框 ──

        // 宽度输入框
        let wField = NSTextField(frame: .zero)
        wField.translatesAutoresizingMaskIntoConstraints = false
        wField.placeholderString = NSLocalizedString("action.resize.widthPlaceholder", comment: "Width (px)")
        wField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        wField.isBezeled = true
        wField.bezelStyle = .roundedBezel
        wField.focusRingType = .exterior
        wField.alignment = .right
        self.widthField = wField

        // 高度输入框
        let hField = NSTextField(frame: .zero)
        hField.translatesAutoresizingMaskIntoConstraints = false
        hField.placeholderString = NSLocalizedString("action.resize.heightPlaceholder", comment: "Height (px)")
        hField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        hField.isBezeled = true
        hField.bezelStyle = .roundedBezel
        hField.focusRingType = .exterior
        hField.alignment = .right
        self.heightField = hField

        // 百分比输入框
        let pField = NSTextField(frame: .zero)
        pField.translatesAutoresizingMaskIntoConstraints = false
        pField.placeholderString = NSLocalizedString("action.resize.percentPlaceholder", comment: "e.g. 50")
        pField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        pField.isBezeled = true
        pField.bezelStyle = .roundedBezel
        pField.focusRingType = .exterior
        pField.alignment = .right
        self.percentField = pField

        // 错误提示标签
        let errLabel = NSTextField(labelWithString: "")
        errLabel.translatesAutoresizingMaskIntoConstraints = false
        errLabel.font = NSFont.systemFont(ofSize: 11)
        errLabel.textColor = .systemRed
        errLabel.isHidden = true
        self.errorLabel = errLabel

        // 模式切换分段控件
        let segment = NSSegmentedControl(labels: [
            NSLocalizedString("action.resize.modeWidth", comment: "Width"),
            NSLocalizedString("action.resize.modeDimensions", comment: "W × H"),
            NSLocalizedString("action.resize.modePercent", comment: "Percent"),
        ], trackingMode: .selectOne, target: nil, action: nil)
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.selectedSegment = 0
        segment.segmentDistribution = .fillEqually
        self.modeSegment = segment

        // 创建行容器
        let wRow = NSView(frame: .zero)
        wRow.translatesAutoresizingMaskIntoConstraints = false
        self.widthRow = wRow

        let hRow = NSView(frame: .zero)
        hRow.translatesAutoresizingMaskIntoConstraints = false
        hRow.isHidden = true
        self.heightRow = hRow

        let pRow = NSView(frame: .zero)
        pRow.translatesAutoresizingMaskIntoConstraints = false
        pRow.isHidden = true
        self.percentRow = pRow

        // ── 计算窗口尺寸和位置 ──
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 280
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelX = screenFrame.midX - panelWidth / 2
        let panelY = screenFrame.midY - panelHeight / 2 + 100

        let contentRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = NSLocalizedString("action.resize.customTitle", comment: "Custom Resize")
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false

        // 设置模式切换 target/action（必须在 super.init 后设置）
        modeSegment.target = self
        modeSegment.action = #selector(modeChanged(_:))

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 关键覆盖：确保窗口能成为 key window

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - UI 布局

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // ── 标题区域 ──
        let iconView = NSImageView(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconView.contentTintColor = .controlAccentColor

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("action.resize.customTitle", comment: "Custom Resize"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)

        let messageLabel = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "action.resize.customMessageV2",
            comment: "Choose a resize mode and enter the target size."
        ))
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor

        // ── 宽度行 ──
        let widthLabel = NSTextField(labelWithString: NSLocalizedString("action.resize.widthLabel", comment: "Width:"))
        widthLabel.translatesAutoresizingMaskIntoConstraints = false
        widthLabel.font = NSFont.systemFont(ofSize: 13)
        widthLabel.alignment = .right

        let widthUnitLabel = NSTextField(labelWithString: "px")
        widthUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        widthUnitLabel.font = NSFont.systemFont(ofSize: 13)
        widthUnitLabel.textColor = .secondaryLabelColor

        widthRow.addSubview(widthLabel)
        widthRow.addSubview(widthField)
        widthRow.addSubview(widthUnitLabel)

        NSLayoutConstraint.activate([
            widthLabel.leadingAnchor.constraint(equalTo: widthRow.leadingAnchor),
            widthLabel.centerYAnchor.constraint(equalTo: widthRow.centerYAnchor),
            widthLabel.widthAnchor.constraint(equalToConstant: 60),

            widthField.leadingAnchor.constraint(equalTo: widthLabel.trailingAnchor, constant: 8),
            widthField.centerYAnchor.constraint(equalTo: widthRow.centerYAnchor),
            widthField.heightAnchor.constraint(equalToConstant: 26),

            widthUnitLabel.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 6),
            widthUnitLabel.centerYAnchor.constraint(equalTo: widthRow.centerYAnchor),
            widthUnitLabel.trailingAnchor.constraint(equalTo: widthRow.trailingAnchor),
            widthUnitLabel.widthAnchor.constraint(equalToConstant: 30),

            widthRow.heightAnchor.constraint(equalToConstant: 28),
        ])

        // ── 高度行 ──
        let heightLabel = NSTextField(labelWithString: NSLocalizedString("action.resize.heightLabel", comment: "Height:"))
        heightLabel.translatesAutoresizingMaskIntoConstraints = false
        heightLabel.font = NSFont.systemFont(ofSize: 13)
        heightLabel.alignment = .right

        let heightUnitLabel = NSTextField(labelWithString: "px")
        heightUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        heightUnitLabel.font = NSFont.systemFont(ofSize: 13)
        heightUnitLabel.textColor = .secondaryLabelColor

        heightRow.addSubview(heightLabel)
        heightRow.addSubview(heightField)
        heightRow.addSubview(heightUnitLabel)

        NSLayoutConstraint.activate([
            heightLabel.leadingAnchor.constraint(equalTo: heightRow.leadingAnchor),
            heightLabel.centerYAnchor.constraint(equalTo: heightRow.centerYAnchor),
            heightLabel.widthAnchor.constraint(equalToConstant: 60),

            heightField.leadingAnchor.constraint(equalTo: heightLabel.trailingAnchor, constant: 8),
            heightField.centerYAnchor.constraint(equalTo: heightRow.centerYAnchor),
            heightField.heightAnchor.constraint(equalToConstant: 26),

            heightUnitLabel.leadingAnchor.constraint(equalTo: heightField.trailingAnchor, constant: 6),
            heightUnitLabel.centerYAnchor.constraint(equalTo: heightRow.centerYAnchor),
            heightUnitLabel.trailingAnchor.constraint(equalTo: heightRow.trailingAnchor),
            heightUnitLabel.widthAnchor.constraint(equalToConstant: 30),

            heightRow.heightAnchor.constraint(equalToConstant: 28),
        ])

        // ── 百分比行 ──
        let percentLabel = NSTextField(labelWithString: NSLocalizedString("action.resize.percentLabel", comment: "Scale:"))
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = NSFont.systemFont(ofSize: 13)
        percentLabel.alignment = .right

        let percentUnitLabel = NSTextField(labelWithString: "%")
        percentUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        percentUnitLabel.font = NSFont.systemFont(ofSize: 13)
        percentUnitLabel.textColor = .secondaryLabelColor

        percentRow.addSubview(percentLabel)
        percentRow.addSubview(percentField)
        percentRow.addSubview(percentUnitLabel)

        NSLayoutConstraint.activate([
            percentLabel.leadingAnchor.constraint(equalTo: percentRow.leadingAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: percentRow.centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 60),

            percentField.leadingAnchor.constraint(equalTo: percentLabel.trailingAnchor, constant: 8),
            percentField.centerYAnchor.constraint(equalTo: percentRow.centerYAnchor),
            percentField.heightAnchor.constraint(equalToConstant: 26),

            percentUnitLabel.leadingAnchor.constraint(equalTo: percentField.trailingAnchor, constant: 6),
            percentUnitLabel.centerYAnchor.constraint(equalTo: percentRow.centerYAnchor),
            percentUnitLabel.trailingAnchor.constraint(equalTo: percentRow.trailingAnchor),
            percentUnitLabel.widthAnchor.constraint(equalToConstant: 30),

            percentRow.heightAnchor.constraint(equalToConstant: 28),
        ])

        // ── 按钮 ──
        let okButton = NSButton(
            title: NSLocalizedString("common.ok", comment: "OK"),
            target: self,
            action: #selector(okClicked)
        )
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        okButton.controlSize = .regular

        let cancelButton = NSButton(
            title: NSLocalizedString("common.cancel", comment: "Cancel"),
            target: self,
            action: #selector(cancelClicked)
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .regular

        // ── 添加到视图层级 ──
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(modeSegment)
        contentView.addSubview(widthRow)
        contentView.addSubview(heightRow)
        contentView.addSubview(percentRow)
        contentView.addSubview(errorLabel)
        contentView.addSubview(okButton)
        contentView.addSubview(cancelButton)

        // ── Auto Layout ──
        NSLayoutConstraint.activate([
            // 图标
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            // 标题
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            // 说明文字
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            messageLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),

            // 模式切换
            modeSegment.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            modeSegment.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            modeSegment.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
            modeSegment.heightAnchor.constraint(equalToConstant: 24),

            // 宽度行
            widthRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            widthRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            widthRow.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 14),

            // 高度行
            heightRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            heightRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            heightRow.topAnchor.constraint(equalTo: widthRow.bottomAnchor, constant: 8),

            // 百分比行
            percentRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            percentRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            percentRow.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 14),

            // 错误标签
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            errorLabel.topAnchor.constraint(equalTo: heightRow.bottomAnchor, constant: 6),

            // 按钮（右下角）
            okButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            okButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            okButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        // 初始模式
        updateVisibility(for: .width)
    }

    // MARK: - 模式切换

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let mode = ResizeMode(rawValue: sender.selectedSegment) else { return }
        updateVisibility(for: mode)
        errorLabel.isHidden = true
    }

    private func updateVisibility(for mode: ResizeMode) {
        switch mode {
        case .width:
            widthRow.isHidden = false
            heightRow.isHidden = true
            percentRow.isHidden = true
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(self?.widthField)
            }

        case .dimensions:
            widthRow.isHidden = false
            heightRow.isHidden = false
            percentRow.isHidden = true
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(self?.widthField)
            }

        case .percentage:
            widthRow.isHidden = true
            heightRow.isHidden = true
            percentRow.isHidden = false
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(self?.percentField)
            }
        }
    }

    // MARK: - 显示窗口并运行模态

    func showAndRun() {
        // 1. 强制激活当前进程（关键！FinderSync 扩展默认不是前台进程）
        if let app = NSApp {
            app.setActivationPolicy(.accessory)
            app.activate(ignoringOtherApps: true)
        }

        // 2. 显示窗口
        self.center()
        self.makeKeyAndOrderFront(nil)

        // 3. 多次尝试获取焦点，应对 macOS 窗口动画的延迟
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp?.activate(ignoringOtherApps: true)
            self.makeKey()
            self.makeFirstResponder(self.widthField)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            NSApp?.activate(ignoringOtherApps: true)
            self.makeKey()
            self.makeFirstResponder(self.widthField)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.makeKey()
            self.makeFirstResponder(self.widthField)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.makeFirstResponder(self.widthField)
        }

        // 4. 运行模态循环（阻塞直到用户点击确定或取消）
        NSApp?.runModal(for: self)
    }

    // MARK: - 按钮动作

    @objc private func okClicked() {
        guard let mode = ResizeMode(rawValue: modeSegment.selectedSegment) else { return }

        switch mode {
        case .width:
            let input = widthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let w = Int(input), w > 0, w <= 100000 else {
                showError(NSLocalizedString(
                    "action.resize.invalidWidth",
                    comment: "Please enter a valid width (1–100000)."
                ))
                return
            }
            let option = ImageResizeOption(label: "\(w)px", kind: .width(w))
            finishWith(option)

        case .dimensions:
            let wInput = widthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let hInput = heightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let w = Int(wInput), w > 0, w <= 100000 else {
                showError(NSLocalizedString(
                    "action.resize.invalidWidth",
                    comment: "Please enter a valid width (1–100000)."
                ))
                return
            }
            guard let h = Int(hInput), h > 0, h <= 100000 else {
                showError(NSLocalizedString(
                    "action.resize.invalidHeight",
                    comment: "Please enter a valid height (1–100000)."
                ))
                return
            }
            let option = ImageResizeOption(label: "\(w)×\(h)", kind: .dimensions(width: w, height: h))
            finishWith(option)

        case .percentage:
            let input = percentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            // Allow user to type with or without % suffix
            let cleaned = input.hasSuffix("%") ? String(input.dropLast()) : input
            guard let pct = Int(cleaned), pct > 0, pct <= 1000 else {
                showError(NSLocalizedString(
                    "action.resize.invalidPercent",
                    comment: "Please enter a valid percentage (1–1000)."
                ))
                return
            }
            let option = ImageResizeOption(label: "\(pct)%", kind: .percentage(pct))
            finishWith(option)
        }
    }

    @objc private func cancelClicked() {
        finishWith(nil)
    }

    // MARK: - 关闭处理

    /// 用户点击窗口关闭按钮时视为取消
    override func close() {
        finishWith(nil)
    }

    // MARK: - 键盘快捷键处理

    override func keyDown(with event: NSEvent) {
        // Handle Escape key even if no responder catches it
        if event.keyCode == 53 { // Escape
            cancelClicked()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - 辅助方法

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false

        // 震动动画
        let activeField: NSTextField
        switch ResizeMode(rawValue: modeSegment.selectedSegment) {
        case .percentage:
            activeField = percentField
        default:
            activeField = widthField
        }

        activeField.wantsLayer = true
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -6, 6, -4, 4, -2, 2, 0].map { (activeField.frame.midX + $0) }
        animation.duration = 0.4
        animation.isAdditive = false
        activeField.layer?.add(animation, forKey: "shake")
    }

    private func finishWith(_ option: ImageResizeOption?) {
        onComplete?(option)
        onComplete = nil
        NSApp?.stopModal()
        orderOut(nil)
    }
}
