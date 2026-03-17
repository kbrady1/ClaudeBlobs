import AppKit

enum AppIcon {
    /// Generates the app icon as an NSImage at the given size.
    /// Uses the agent sprite aesthetic: rounded rectangle with a face.
    static func create(size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            // Background: blue (working state color)
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: w * 0.04, dy: h * 0.04),
                                    xRadius: w * 0.2, yRadius: h * 0.2)
            NSColor(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0).setFill()
            body.fill()

            // Subtle inner shadow / border
            NSColor(white: 0, alpha: 0.12).setStroke()
            body.lineWidth = w * 0.01
            body.stroke()

            // Face features in white
            NSColor.white.setFill()
            NSColor.white.setStroke()

            let faceW = w * 0.55
            let faceH = h * 0.40
            let faceX = (w - faceW) / 2
            let faceY = (h - faceH) / 2 - h * 0.02
            let lineWidth = max(2, w * 0.035)

            // Left eye: chevron ^
            let leftEye = NSBezierPath()
            leftEye.lineWidth = lineWidth
            leftEye.lineCapStyle = .round
            leftEye.lineJoinStyle = .round
            leftEye.move(to: NSPoint(x: faceX + faceW * 0.14, y: faceY + faceH * 0.52))
            leftEye.line(to: NSPoint(x: faceX + faceW * 0.28, y: faceY + faceH * 0.72))
            leftEye.line(to: NSPoint(x: faceX + faceW * 0.42, y: faceY + faceH * 0.52))
            leftEye.stroke()

            // Right eye: chevron ^
            let rightEye = NSBezierPath()
            rightEye.lineWidth = lineWidth
            rightEye.lineCapStyle = .round
            rightEye.lineJoinStyle = .round
            rightEye.move(to: NSPoint(x: faceX + faceW * 0.58, y: faceY + faceH * 0.52))
            rightEye.line(to: NSPoint(x: faceX + faceW * 0.72, y: faceY + faceH * 0.72))
            rightEye.line(to: NSPoint(x: faceX + faceW * 0.86, y: faceY + faceH * 0.52))
            rightEye.stroke()

            // Smile: arc ‿
            let smile = NSBezierPath()
            smile.lineWidth = lineWidth
            smile.lineCapStyle = .round
            let smileY = faceY + faceH * 0.30
            smile.move(to: NSPoint(x: faceX + faceW * 0.18, y: smileY))
            let smileCP = NSPoint(x: faceX + faceW * 0.50, y: smileY - faceH * 0.40)
            smile.curve(to: NSPoint(x: faceX + faceW * 0.82, y: smileY),
                        controlPoint1: smileCP, controlPoint2: smileCP)
            smile.stroke()

            return true
        }
    }

    /// Writes the app icon as an .icns file to the given URL.
    static func writeICNS(to url: URL) throws {
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

        let iconsetURL = url.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        for (px, name) in sizes {
            let image = create(size: CGFloat(px))
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: iconsetURL.appendingPathComponent("icon_\(name).png"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetURL.path, "-o", url.path]
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: iconsetURL)
    }
}
