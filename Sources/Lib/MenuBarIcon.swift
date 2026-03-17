import AppKit

enum MenuBarIcon {
    /// Creates a template NSImage of the agent face for the menu bar.
    /// Filled rounded rectangle with the happy ^‿^ face (StartingFace style).
    /// Template images automatically adapt to light/dark menu bar.
    static func create(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Filled rounded rectangle body
            let bodyInset: CGFloat = w * 0.05
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: bodyInset, dy: bodyInset),
                                    xRadius: w * 0.22, yRadius: h * 0.22)
            body.fill()

            // Punch out face features using .clear blend mode so they become transparent
            // (template images use alpha: opaque = visible, transparent = invisible)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.setBlendMode(.clear)

            let lw = max(1, w * 0.07)

            // Face region (coords are non-flipped: 0,0 = bottom-left)
            let faceW = w * 0.7
            let faceH = h * 0.5
            let faceX = (w - faceW) / 2
            let faceY = (h - faceH) / 2

            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Left eye: chevron ^
            ctx.beginPath()
            ctx.move(to: CGPoint(x: faceX + faceW * 0.14, y: faceY + faceH * 0.52))
            ctx.addLine(to: CGPoint(x: faceX + faceW * 0.28, y: faceY + faceH * 0.72))
            ctx.addLine(to: CGPoint(x: faceX + faceW * 0.42, y: faceY + faceH * 0.52))
            ctx.strokePath()

            // Right eye: chevron ^
            ctx.beginPath()
            ctx.move(to: CGPoint(x: faceX + faceW * 0.58, y: faceY + faceH * 0.52))
            ctx.addLine(to: CGPoint(x: faceX + faceW * 0.72, y: faceY + faceH * 0.72))
            ctx.addLine(to: CGPoint(x: faceX + faceW * 0.86, y: faceY + faceH * 0.52))
            ctx.strokePath()

            // Smile: arc curve ‿
            let smileY = faceY + faceH * 0.30
            let smileCP = CGPoint(x: faceX + faceW * 0.50, y: smileY - faceH * 0.40)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: faceX + faceW * 0.18, y: smileY))
            ctx.addCurve(to: CGPoint(x: faceX + faceW * 0.82, y: smileY),
                         control1: smileCP, control2: smileCP)
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct StrokeStyle {
    let lineWidth: CGFloat
}
