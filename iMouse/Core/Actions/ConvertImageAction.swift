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
//  macOS 的 ImageIO (CGImageDestination) 不支持写入 WebP 格式，
//  虽然可以通过 CGImageSource 读取 WebP。
//  解决方案：优先尝试系统自带的 ImageIO，如果失败（WebP 等情况），
//  则回退到调用 cwebp 命令行工具（通过 Homebrew 安装：brew install webp）。
//  如果 cwebp 也不可用，则提示用户安装。
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

        // 在后台线程执行转换（图片可能很大）
        DispatchQueue.global(qos: .userInitiated).async {
            var failedFiles: [String] = []
            var webpToolMissing = false

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
                case .failure(let reason):
                    failedFiles.append(item.name)
                    if reason == .webpToolNotFound {
                        webpToolMissing = true
                    }
                }
            }

            // 如果 cwebp 工具缺失，显示专门的安装提示
            if webpToolMissing {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: NSLocalizedString("action.convert.error.title", comment: "转换失败"),
                        message: NSLocalizedString(
                            "action.convert.error.webpNotSupported",
                            comment: "macOS does not natively support writing WebP format.\n\nTo enable WebP conversion, please install the WebP tools via Homebrew:\n\n  brew install webp\n\nThen try again."
                        )
                    )
                }
            } else if !failedFiles.isEmpty {
                // 如果有转换失败的文件，在主线程上显示提示
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

    // MARK: - 转换结果

    private enum ConvertResult {
        case success
        case failure(FailureReason)
    }

    private enum FailureReason {
        case generic
        case webpToolNotFound
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

        // WebP 特殊处理：macOS ImageIO 不支持写入 WebP
        if targetFormat == .webp {
            return convertToWebP(sourceURL: sourceURL, baseName: baseName, quality: quality)
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

    // MARK: - WebP 转换（使用 cwebp 命令行工具）

    /// 使用 cwebp 命令行工具将图片转换为 WebP 格式。
    ///
    /// macOS 原生 ImageIO 不支持写入 WebP 格式。
    /// cwebp 是 Google 提供的官方 WebP 编码工具，可通过 Homebrew 安装。
    ///
    /// 转换策略：
    /// 1. 如果源图片不是 PNG，先将其转为临时 PNG 文件（cwebp 支持 PNG/JPEG/TIFF/WebP 输入）
    /// 2. 调用 cwebp 将源文件（或临时 PNG）转换为 WebP
    /// 3. 清理临时文件
    ///
    /// - Parameters:
    ///   - sourceURL: 原始图片文件的 URL
    ///   - baseName: 原始文件的基础名称（不含扩展名）
    ///   - quality: 图片质量（0.0 ~ 1.0）
    /// - Returns: 转换结果
    private func convertToWebP(
        sourceURL: URL,
        baseName: String,
        quality: Double
    ) -> ConvertResult {

        // 查找 cwebp 工具
        guard let cwebpPath = findCwebp() else {
            NSLog("[iMouse ConvertImage] cwebp not found. WebP writing is not supported without it.")
            return .failure(.webpToolNotFound)
        }

        NSLog("[iMouse ConvertImage] Using cwebp at: %@", cwebpPath)

        let destURL = uniqueOutputURL(
            sourceURL: sourceURL,
            baseName: baseName,
            targetExtension: "webp"
        )

        // cwebp 支持的输入格式: PNG, JPEG, TIFF, WebP, (and raw Y'CbCr)
        // 对于其他格式（如 HEIC, BMP, GIF），需要先转为 PNG
        let sourceExt = sourceURL.pathExtension.lowercased()
        let cwebpNativeInputs = ["png", "jpg", "jpeg", "tif", "tiff", "webp"]

        var inputURL = sourceURL
        var tempFileURL: URL? = nil

        if !cwebpNativeInputs.contains(sourceExt) {
            // 需要先转换为 PNG 作为中间格式
            let tempDir = FileManager.default.temporaryDirectory
            let tempPNG = tempDir.appendingPathComponent("imouse_convert_\(UUID().uuidString.prefix(8)).png")

            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                  let dest = CGImageDestinationCreateWithURL(tempPNG as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return .failure(.generic)
            }

            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else {
                return .failure(.generic)
            }

            inputURL = tempPNG
            tempFileURL = tempPNG
        }

        // 执行 cwebp 转换
        let qualityPercent = Int(quality * 100)
        let result = runProcess(
            executablePath: cwebpPath,
            arguments: [
                "-q", "\(qualityPercent)",
                inputURL.path(percentEncoded: false),
                "-o", destURL.path(percentEncoded: false)
            ]
        )

        // 清理临时文件
        if let tempFile = tempFileURL {
            try? FileManager.default.removeItem(at: tempFile)
        }

        if result {
            NSLog("[iMouse ConvertImage] WebP conversion succeeded: %@", destURL.path(percentEncoded: false))
            return .success
        } else {
            // 如果输出文件已创建但可能损坏，清理掉
            if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: destURL)
            }
            return .failure(.generic)
        }
    }

    /// 在常见路径中查找 cwebp 可执行文件
    private func findCwebp() -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/cwebp",       // Apple Silicon Homebrew
            "/usr/local/bin/cwebp",          // Intel Homebrew
            "/opt/local/bin/cwebp",          // MacPorts
            "/usr/bin/cwebp",                // System (unlikely but check)
        ]

        let fm = FileManager.default
        for path in searchPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 尝试通过 zsh -l -c "which cwebp" 来查找（处理用户自定义 PATH）
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which cwebp"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let output, !output.isEmpty, fm.isExecutableFile(atPath: output) {
                    return output
                }
            }
        } catch {
            NSLog("[iMouse ConvertImage] Failed to run 'which cwebp': %@", error.localizedDescription)
        }

        return nil
    }

    /// 运行外部进程并等待完成
    ///
    /// - Parameters:
    ///   - executablePath: 可执行文件的完整路径
    ///   - arguments: 命令行参数
    /// - Returns: 进程是否成功完成（exit code == 0）
    private func runProcess(executablePath: String, arguments: [String]) -> Bool {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                NSLog("[iMouse ConvertImage] Process failed (exit %d): %@\nstderr: %@",
                      process.terminationStatus,
                      ([executablePath] + arguments).joined(separator: " "),
                      errStr)
                return false
            }
            return true
        } catch {
            NSLog("[iMouse ConvertImage] Failed to launch process: %@", error.localizedDescription)
            return false
        }
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
