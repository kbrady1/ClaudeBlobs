import AppKit
import SwiftUI

/// Non-activating floating panel that sits just below the menu bar.
/// Fixed size — SwiftUI handles all visual transitions internally.
final class HUDPanel: NSPanel {
    static let panelWidth: CGFloat = 960
    static let panelHeight: CGFloat = 160

    /// Safe area top inset of the screen this panel is on (notch height).
    /// Exposed so the SwiftUI content can pad below the notch while
    /// letting the expanded background extend behind it.
    var notchInset: CGFloat = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    /// Position the panel centered horizontally at the very top of the screen.
    /// On notched displays the panel extends behind the notch area so the
    /// expanded background can fill up to the screen edge.
    func positionAtTop(of screen: NSScreen) {
        notchInset = screen.safeAreaInsets.top
        let totalHeight = Self.panelHeight + notchInset
        let x = screen.frame.midX - Self.panelWidth / 2
        let y = screen.frame.maxY - totalHeight
        setContentSize(NSSize(width: Self.panelWidth, height: totalHeight))
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
