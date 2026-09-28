#!/usr/bin/env swift
// Generates AppIcon.icns for the app bundle.
// Usage: swift generate-icon.swift <output-path>

import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let w = rect.width
        let h = rect.height

        // Blue rounded rectangle body
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: w * 0.04, dy: h * 0.04),
                                xRadius: w * 0.2, yRadius: h * 0.2)
        NSColor(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0).setFill()
        body.fill()

        // Subtle border
        NSColor(white: 0, alpha: 0.12).setStroke()
        body.lineWidth = w * 0.01
        body.stroke()

        // White face features
        NSColor.white.setStroke()
        let lw = max(2, w * 0.035)

        let faceW = w * 0.55
        let faceH = h * 0.40
        let faceX = (w - faceW) / 2
        let faceY = (h - faceH) / 2 - h * 0.02

        // Left eye: chevron ^
        let leftEye = NSBezierPath()
        leftEye.lineWidth = lw
        leftEye.lineCapStyle = .round
        leftEye.lineJoinStyle = .round
        leftEye.move(to: NSPoint(x: faceX + faceW * 0.14, y: faceY + faceH * 0.52))
        leftEye.line(to: NSPoint(x: faceX + faceW * 0.28, y: faceY + faceH * 0.72))
        leftEye.line(to: NSPoint(x: faceX + faceW * 0.42, y: faceY + faceH * 0.52))
        leftEye.stroke()

        // Right eye: chevron ^
        let rightEye = NSBezierPath()
        rightEye.lineWidth = lw
        rightEye.lineCapStyle = .round
        rightEye.lineJoinStyle = .round
        rightEye.move(to: NSPoint(x: faceX + faceW * 0.58, y: faceY + faceH * 0.52))
        rightEye.line(to: NSPoint(x: faceX + faceW * 0.72, y: faceY + faceH * 0.72))
        rightEye.line(to: NSPoint(x: faceX + faceW * 0.86, y: faceY + faceH * 0.52))
        rightEye.stroke()

        // Smile: arc ‿
        let smile = NSBezierPath()
        smile.lineWidth = lw
        smile.lineCapStyle = .round
        let smileY = faceY + faceH * 0.30
        let cp = NSPoint(x: faceX + faceW * 0.50, y: smileY - faceH * 0.40)
        smile.move(to: NSPoint(x: faceX + faceW * 0.18, y: smileY))
        smile.curve(to: NSPoint(x: faceX + faceW * 0.82, y: smileY),
                    controlPoint1: cp, controlPoint2: cp)
        smile.stroke()

        return true
    }
}

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate-icon.swift <output.icns>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: outputPath)

// ICNS element type for each rendered pixel size. The file is written directly
// because `iconutil` rejects every iconset on some macOS releases (26.7).
let elements: [(px: Int, type: String)] = [
    (16, "icp4"),    // 16x16
    (32, "icp5"),    // 32x32
    (32, "ic11"),    // 16x16@2x
    (64, "icp6"),    // 64x64
    (64, "ic12"),    // 32x32@2x
    (128, "ic07"),   // 128x128
    (256, "ic08"),   // 256x256
    (256, "ic13"),   // 128x128@2x
    (512, "ic09"),   // 512x512
    (512, "ic14"),   // 256x256@2x
    (1024, "ic10"),  // 512x512@2x
]

func bigEndian(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

var pngCache: [Int: Data] = [:]
var body = Data()
for (px, type) in elements {
    if pngCache[px] == nil {
        // Draw into an explicit bitmap so the pixel size does not depend on the screen scale.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            fputs("Failed to create bitmap for \(px)px\n", stderr)
            exit(1)
        }
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawIcon(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Failed to render \(px)px\n", stderr)
            exit(1)
        }
        pngCache[px] = png
    }
    let png = pngCache[px]!
    body.append(type.data(using: .ascii)!)
    body.append(bigEndian(UInt32(8 + png.count)))
    body.append(png)
}

var icns = "icns".data(using: .ascii)!
icns.append(bigEndian(UInt32(8 + body.count)))
icns.append(body)

do {
    try icns.write(to: outputURL)
    print("Generated \(outputPath)")
} catch {
    fputs("Failed to write \(outputPath): \(error)\n", stderr)
    exit(1)
}
