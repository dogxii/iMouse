#!/usr/bin/env swift

// generate_icon.swift
// Generates the iMouse app icon (1024x1024 PNG) using CoreGraphics.
// Usage: swift generate_icon.swift [output_path]
// Default output: ../iMouse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

import Foundation
import CoreGraphics
import AppKit
import CoreText

let size = 1024
let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
    outputPath = scriptDir
        .appendingPathComponent("../iMouse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
        .path
}

// Create bitmap context
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Cannot create CGContext")
}

let s = CGFloat(size)

// ── Helper functions ──

func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    return CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGMutablePath {
    let path = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    return path
}

// ── 1. Background: macOS-style rounded rectangle with gradient ──

let iconInset: CGFloat = s * 0.02
let iconRect = CGRect(x: iconInset, y: iconInset, width: s - iconInset * 2, height: s - iconInset * 2)
let cornerRadius = s * 0.22

ctx.saveGState()
let bgPath = roundedRectPath(iconRect, radius: cornerRadius)
ctx.addPath(bgPath)
ctx.clip()

// Gradient: teal-blue
let gradientColors = [
    cgColor(0.15, 0.60, 0.82),   // top: vivid teal-blue
    cgColor(0.06, 0.25, 0.50),   // bottom: deep navy
] as CFArray
let gradientLocations: [CGFloat] = [0.0, 1.0]
let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: s / 2, y: s - iconInset),
    end: CGPoint(x: s / 2, y: iconInset),
    options: []
)

// Subtle top shine
let shineColors = [
    cgColor(1, 1, 1, 0.12),
    cgColor(1, 1, 1, 0.0),
] as CFArray
let shineGrad = CGGradient(colorsSpace: colorSpace, colors: shineColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    shineGrad,
    start: CGPoint(x: s / 2, y: s - iconInset),
    end: CGPoint(x: s / 2, y: s * 0.55),
    options: []
)

ctx.restoreGState()

// Re-clip to icon shape for everything that follows
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// ── 2. Draw context menu card (right side) ──
// Note: card and cursor positions shifted up by ~4% for better visual centering

let cardX = s * 0.40
let cardY = s * 0.19
let cardW = s * 0.46
let cardH = s * 0.55
let cardRadius: CGFloat = s * 0.032
let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)

// Card shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 28, color: cgColor(0, 0, 0, 0.45))
let cardPath = roundedRectPath(cardRect, radius: cardRadius)
ctx.addPath(cardPath)
ctx.setFillColor(cgColor(0.96, 0.96, 0.97))
ctx.fillPath()
ctx.restoreGState()

// Card fill (semi-transparent white, like macOS menus)
ctx.addPath(cardPath)
ctx.setFillColor(cgColor(0.97, 0.97, 0.98, 0.96))
ctx.fillPath()

// ── Menu items ──
let itemCount = 5
let menuPadX = cardW * 0.08
let menuPadY = cardH * 0.06
let usableH = cardH - menuPadY * 2
let separatorAfter = 3  // separator after item index 3 (0-based)
let separatorGap: CGFloat = usableH * 0.04
let totalItemH = usableH - separatorGap
let itemH = totalItemH / CGFloat(itemCount)
let highlightIndex = 1

for i in 0..<itemCount {
    // Calculate Y position (top-down in CG means high Y = top)
    var itemY = cardY + cardH - menuPadY - CGFloat(i + 1) * itemH
    if i >= separatorAfter {
        itemY -= separatorGap
    }

    let itemRect = CGRect(
        x: cardX + menuPadX * 0.5,
        y: itemY + itemH * 0.08,
        width: cardW - menuPadX,
        height: itemH * 0.84
    )

    // Highlighted item
    if i == highlightIndex {
        let hlPath = roundedRectPath(itemRect, radius: s * 0.012)
        ctx.addPath(hlPath)
        ctx.setFillColor(cgColor(0.20, 0.50, 0.90, 0.92))
        ctx.fillPath()
    }

    // Icon circle
    let iconDia = itemH * 0.36
    let iconCX = cardX + menuPadX + iconDia * 0.6
    let iconCY = itemY + itemH * 0.5
    let iconCircleRect = CGRect(
        x: iconCX - iconDia / 2,
        y: iconCY - iconDia / 2,
        width: iconDia,
        height: iconDia
    )

    if i == highlightIndex {
        ctx.setFillColor(cgColor(1, 1, 1, 0.90))
    } else {
        ctx.setFillColor(cgColor(0.50, 0.50, 0.55, 0.50))
    }
    ctx.fillEllipse(in: iconCircleRect)

    // Text bar
    let textX = iconCX + iconDia / 2 + menuPadX * 0.6
    let textBarH = iconDia * 0.50
    let textBarY = iconCY - textBarH / 2
    let widthFactors: [CGFloat] = [0.52, 0.68, 0.42, 0.55, 0.38]
    let maxTextW = cardX + cardW - menuPadX - textX
    let textBarW = maxTextW * widthFactors[i]
    let textBarRect = CGRect(x: textX, y: textBarY, width: textBarW, height: textBarH)
    let textBarPath = roundedRectPath(textBarRect, radius: textBarH / 2)
    ctx.addPath(textBarPath)

    if i == highlightIndex {
        ctx.setFillColor(cgColor(1, 1, 1, 0.88))
    } else {
        ctx.setFillColor(cgColor(0.55, 0.55, 0.60, 0.30))
    }
    ctx.fillPath()

    // Separator
    if i == separatorAfter - 1 {
        let sepY = itemY - separatorGap * 0.5
        ctx.setStrokeColor(cgColor(0.72, 0.72, 0.74, 0.40))
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: cardX + menuPadX, y: sepY))
        ctx.addLine(to: CGPoint(x: cardX + cardW - menuPadX, y: sepY))
        ctx.strokePath()
    }
}

// ── 3. Draw macOS-style mouse cursor ──

// The cursor tip is at the upper-left area, pointing upper-left
// In CG coordinates: (0,0) = bottom-left, Y increases upward
let tipX = s * 0.18
let tipY = s * 0.80
let cs = s * 0.55  // overall cursor height

// Classic macOS arrow cursor proportions
// Outer shape (black outline)
let outerArrow = CGMutablePath()
outerArrow.move(to: CGPoint(x: tipX, y: tipY))                                        // 1: tip
outerArrow.addLine(to: CGPoint(x: tipX, y: tipY - cs * 0.92))                         // 2: bottom of left edge
outerArrow.addLine(to: CGPoint(x: tipX + cs * 0.20, y: tipY - cs * 0.70))             // 3: notch inner
outerArrow.addLine(to: CGPoint(x: tipX + cs * 0.40, y: tipY - cs * 1.05))             // 4: right leg outer bottom
outerArrow.addLine(to: CGPoint(x: tipX + cs * 0.52, y: tipY - cs * 0.96))             // 5: right leg outer right
outerArrow.addLine(to: CGPoint(x: tipX + cs * 0.32, y: tipY - cs * 0.62))             // 6: right leg inner
outerArrow.addLine(to: CGPoint(x: tipX + cs * 0.54, y: tipY - cs * 0.62))             // 7: right wing tip
outerArrow.closeSubpath()

// Shadow behind cursor
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 5, height: -6), blur: 20, color: cgColor(0, 0, 0, 0.55))
ctx.addPath(outerArrow)
ctx.setFillColor(cgColor(0.05, 0.05, 0.05))
ctx.fillPath()
ctx.restoreGState()

// Draw black outline again (on top of shadow)
ctx.addPath(outerArrow)
ctx.setFillColor(cgColor(0.05, 0.05, 0.05))
ctx.fillPath()

// Inner white fill (inset from the outer shape)
let inPx = cs * 0.042  // inset amount
let ix = tipX + inPx * 0.8
let iy = tipY - inPx * 1.2
let ics = cs * 0.85  // slightly smaller scale

let innerArrow = CGMutablePath()
innerArrow.move(to: CGPoint(x: ix, y: iy))
innerArrow.addLine(to: CGPoint(x: ix, y: iy - ics * 0.90))
innerArrow.addLine(to: CGPoint(x: ix + ics * 0.19, y: iy - ics * 0.70))
innerArrow.addLine(to: CGPoint(x: ix + ics * 0.38, y: iy - ics * 1.02))
innerArrow.addLine(to: CGPoint(x: ix + ics * 0.47, y: iy - ics * 0.95))
innerArrow.addLine(to: CGPoint(x: ix + ics * 0.28, y: iy - ics * 0.63))
innerArrow.addLine(to: CGPoint(x: ix + ics * 0.47, y: iy - ics * 0.63))
innerArrow.closeSubpath()

ctx.addPath(innerArrow)
ctx.setFillColor(cgColor(1, 1, 1, 0.98))
ctx.fillPath()

// Restore from icon clip
ctx.restoreGState()

// ── 5. Save to PNG ──

guard let image = ctx.makeImage() else {
    fatalError("Cannot create image from context")
}

let url = URL(fileURLWithPath: outputPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
    fatalError("Cannot create image destination at \(outputPath)")
}

CGImageDestinationAddImage(destination, image, nil)

if CGImageDestinationFinalize(destination) {
    print("✅ Icon saved to: \(outputPath)")
} else {
    fatalError("Failed to write PNG to \(outputPath)")
}
