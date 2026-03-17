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

let sizes: [(Int, String)] = [
    (16, "16x16"),
    (32, "16x16@2x"),
    (32, "32x32"),
    (64, "32x32@2x"),
    (128, "128x128"),
    (256, "128x128@2x"),
    (256, "256x256"),
    (512, "256x256@2x"),
    (512, "512x512"),
    (1024, "512x512@2x"),
]

let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (px, name) in sizes {
    let image = drawIcon(size: CGFloat(px))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(name)\n", stderr)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent("icon_\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetURL)

if process.terminationStatus == 0 {
    print("Generated \(outputPath)")
} else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}
