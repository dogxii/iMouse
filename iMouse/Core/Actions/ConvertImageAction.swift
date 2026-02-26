//
//  ConvertImageAction.swift
//  iMouse
//
//  「转换图片格式」动作：将选中的图片文件转换为指定格式（PNG/JPEG/WEBP/HEIC/TIFF/GIF/BMP）。
//  使用 CoreGraphics + ImageIO 框架进行图片读写，无需第三方依赖。
//
//  转换后的文件保存在原文件旁边，命名规则：
//  - 原文件: photo.png
//  - 转换后: photo.jpg （如果目标扩展名与原文件不同，直接换扩展名）
//  - 如果同名文件已存在: photo_converted.jpg、photo_converted 2.jpg、…
//
//  ── WebP 写入说明 ──
//  macOS 的 ImageIO (CGImageDestination) 不支持写入 WebP 格式。
//  FinderSync 扩展运行在沙盒中，无法调用 cwebp 外部进程，
//  也无法访问 /opt/homebrew/bin/ 等沙盒外路径。
//
//  解决方案（与终端/AirDrop 动作相同的委托模式）：
//  - 非 WebP 格式：直接在扩展内用 ImageIO/CoreGraphics 转换（系统框架不受沙盒限制）
//  - WebP 格式：通过 imouse://convert-webp URL scheme 将文件路径委托给主 App
//  - 主 App（非沙盒）接收 URL 后调用 cwebp 命令行工具执行转换
//  - 主 App 的 AppDelegate.handleConvertWebPURL(_:) 处理该 URL
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ConvertImageAction: ContextAction {

    // MARK: - 标识

    let id = "action.convertImage"

    var displayName: String {
        NSLocalizedString("action.convert.name", comment: "转换图片格式")
    }

    var displayDescription: String {
        NSLocalizedString("action.convert.desc", comment: "将选中的图片转换为 PNG、JPEG、WebP 等格式")
    }

    let sfSymbolName = "arrow.triangle.2.circlepath"

    // MARK: - 可见性

    /// 「转换图片格式」仅在选中的文件中包含至少一个图片文件时显示。
    func isVisible(for context: SelectionContext) -> Bool {
        return context.hasImages
    }

    // MARK: - 菜单表示

    /// 显示为子菜单，列出所有启用的目标格式供用户选择。
    func menuItem(for context: SelectionContext) -> MenuItemRepresentation {
        let settings = AppSettings.load()
        let formats = settings.enabledImageFormats

        let children: [(id: String, title: String, icon: NSImage?)] = formats.map { format in
            (
                id: format.rawValue,
                title: format.displayName,
                icon: nil
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
        // submenuId 就是用户选择的目标格式（ImageFormat.rawValue）
        guard let formatRaw = submenuId,
              let targetFormat = ImageFormat(rawValue: formatRaw) else {
            return
        }

        let settings = AppSettings.load()
        let quality = settings.imageConversionQuality

        // 只处理图片文件
        let imageItems = context.imageFiles

        guard !imageItems.isEmpty else { return }

        // WebP 转换需要在非沙盒的主 App 中执行（调用 cwebp 命令行工具）
        // 通过 URL scheme 委托给主 App，与 AirDrop/Terminal 使用相同的模式
        if targetFormat == .webp {
            delegateWebPToMainApp(imageItems: imageItems, quality: quality)
            return
        }

        // 非 WebP 格式：直接在扩展内用 ImageIO/CoreGraphics 转换
        // ImageIO 是系统框架，不受 FinderSync 沙盒限制
        DispatchQueue.global(qos: .userInitiated).async {
            var failedFiles: [String] = []

            for item in imageItems {
                // 跳过已经是目标格式的文件（避免无意义转换）
                if item.pathExtension == targetFormat.fileExtension {
                    continue
                }

                let result = self.convertImage(
                    sourceURL: item.url,
                    baseName: item.nameWithoutExtension,
                    targetFormat: targetFormat,
                    quality: quality
                )

                switch result {
                case .success:
                    break
                case .failure:
                    failedFiles.append(item.name)
                }
            }

            if !failedFiles.isEmpty {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: NSLocalizedString("action.convert.error.title", comment: "转换失败"),
                        message: String(
                            format: NSLocalizedString(
                                "action.convert.error.someFailed",
                                comment: "以下文件转换失败:\n%@"
                            ),
                            failedFiles.joined(separator: "\n")
                        )
                    )
                }
            }
        }
    }

    // MARK: - 委托 WebP 转换给主 App

    /// 通过 imouse://convert-webp URL scheme 将 WebP 转换请求委托给主 App。
    ///
    /// FinderSync 扩展运行在沙盒中，无法调用 cwebp 等外部进程，
    /// 也无法访问 /opt/homebrew/bin/ 等沙盒外路径。
    /// 主 App（非沙盒）接收 URL 后在自己的进程中调用 cwebp 执行转换。
    ///
    /// URL 格式: imouse://convert-webp?files=<newline-separated paths>&quality=<0-100>
    private func delegateWebPToMainApp(imageItems: [FileItem], quality: Double) {
        let paths = imageItems.map { $0.absolutePath }.joined(separator: "\n")
        let qualityInt = Int(quality * 100)

        var components = URLComponents()
        components.scheme = "imouse"
        components.host = "convert-webp"
        components.queryItems = [
            URLQueryItem(name: "files", value: paths),
            URLQueryItem(name: "quality", value: "\(qualityInt)")
        ]

        guard let url = components.url else {
            NSLog("[iMouse ConvertImage] 无法构建 imouse://convert-webp URL")
            return
        }

        NSLog("[iMouse ConvertImage] 委托给主 App 执行 WebP 转换，文件数: %d, quality: %d", imageItems.count, qualityInt)
        NSWorkspace.shared.open(url)
    }

    // MARK: - 转换结果

    private enum ConvertResult {
        case success
        case failure(FailureReason)
    }

    private enum FailureReason {
        case generic
    }

    // MARK: - 核心转换逻辑

    /// 将单个图片文件转换为目标格式并保存。
    ///
    /// - Parameters:
    ///   - sourceURL: 原始图片文件的 URL
    ///   - baseName: 原始文件的基础名称（不含扩展名）
    ///   - targetFormat: 目标图片格式
    ///   - quality: 图片质量（0.0 ~ 1.0），对有损格式如 JPEG/HEIC 生效
    /// - Returns: 转换结果
    private func convertImage(
        sourceURL: URL,
        baseName: String,
        targetFormat: ImageFormat,
        quality: Double
    ) -> ConvertResult {

        // WebP 由主 App 处理（通过 URL scheme 委托），不应走到这里
        // 但保险起见，如果真的调用了，直接返回失败
        if targetFormat == .webp {
            NSLog("[iMouse ConvertImage] ⚠️ WebP 应通过 URL scheme 委托给主 App，不应在扩展中直接调用")
            return .failure(.generic)
        }


        // 1. 使用 ImageIO 读取源图片
        //    CGImageSourceCreateWithURL 可以读取几乎所有常见图片格式
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return .failure(.generic)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return .failure(.generic)
        }

        // 2. 确定目标文件路径
        let destURL = uniqueOutputURL(
            sourceURL: sourceURL,
            baseName: baseName,
            targetExtension: targetFormat.fileExtension
        )

        // 3. 确定目标格式对应的 UTType 标识符
        //    ImageIO 使用 UTType 字符串来确定输出格式
        guard let uti = utiIdentifier(for: targetFormat) else {
            return .failure(.generic)
        }

        // 4. 使用 ImageIO 的 CGImageDestination 写入目标格式
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            uti as CFString,
            1,     // 图片数量（非动图时为 1）
            nil
        ) else {
            return .failure(.generic)
        }

        // 5. 设置输出参数
        var options: [CFString: Any] = [:]

        // 对有损格式设置质量参数
        switch targetFormat {
        case .jpeg, .heic:
            options[kCGImageDestinationLossyCompressionQuality] = quality
        default:
            break
        }

        // 如果源图片带有元数据（EXIF 等），尝试保留
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) {
            // 将源图片的属性合并到输出参数中
            let dict = sourceProperties as NSDictionary
            for (key, value) in dict {
                let cfKey = key as! CFString
                options[cfKey] = value
            }
        }

        CGImageDestinationAddImage(imageDestination, cgImage, options as CFDictionary)

        // 6. 执行写入
        let success = CGImageDestinationFinalize(imageDestination)

        return success ? .success : .failure(.generic)
    }



    // MARK: - 辅助方法

    /// 为给定的 ImageFormat 返回对应的 UTType 标识符字符串。
    /// ImageIO 使用这些标识符来确定输出编码器。
    ///
    /// - Parameter format: 目标图片格式
    /// - Returns: UTType 标识符字符串，不支持的格式返回 nil
    private func utiIdentifier(for format: ImageFormat) -> String? {
        switch format {
        case .png:  return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .tiff: return UTType.tiff.identifier
        case .gif:  return UTType.gif.identifier
        case .bmp:  return UTType.bmp.identifier
        case .heic: return UTType.heic.identifier
        case .webp: return UTType.webP.identifier  // Note: won't work for writing, handled separately
        }
    }

    /// 生成不冲突的输出文件 URL。
    ///
    /// 规则：
    /// 1. 先尝试直接更换扩展名：photo.png → photo.jpg
    /// 2. 如果同名文件已存在，加 _converted 后缀：photo_converted.jpg
    /// 3. 如果还冲突，加编号：photo_converted 2.jpg、photo_converted 3.jpg、…
    ///
    /// - Parameters:
    ///   - sourceURL: 原始文件的 URL
    ///   - baseName: 原始文件的基础名称（不含扩展名）
    ///   - targetExtension: 目标文件扩展名（例如 "jpg"）
    /// - Returns: 一个在同目录下不存在的文件 URL
    private func uniqueOutputURL(
        sourceURL: URL,
        baseName: String,
        targetExtension: String
    ) -> URL {
        let parentDir = sourceURL.deletingLastPathComponent()
        let fm = FileManager.default

        // 第一次尝试：直接更换扩展名
        let firstAttempt = parentDir.appendingPathComponent("\(baseName).\(targetExtension)")
        if !fm.fileExists(atPath: firstAttempt.path(percentEncoded: false)) {
            return firstAttempt
        }

        // 第二次尝试：加 _converted 后缀
        let convertedName = "\(baseName)_converted"
        let secondAttempt = parentDir.appendingPathComponent("\(convertedName).\(targetExtension)")
        if !fm.fileExists(atPath: secondAttempt.path(percentEncoded: false)) {
            return secondAttempt
        }

        // 编号递增
        var counter = 2
        while counter <= 10000 {
            let candidate = parentDir.appendingPathComponent(
                "\(convertedName) \(counter).\(targetExtension)"
            )
            if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            counter += 1
        }

        // 后备方案：使用时间戳
        let timestamp = Int(Date().timeIntervalSince1970)
        return parentDir.appendingPathComponent(
            "\(baseName)_\(timestamp).\(targetExtension)"
        )
    }

    /// 显示错误提示对话框
    private func showAlert(title: String, message: String) {
        let showBlock = {
            NSApp?.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "好"))
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
