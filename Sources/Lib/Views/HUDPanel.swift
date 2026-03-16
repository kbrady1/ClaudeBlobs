import AppKit
import SwiftUI

/// Non-activating floating panel that sits just below the menu bar.
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22),
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

    /// Position the panel top-center of the main screen, just below the menu bar.
    func positionBelowMenuBar() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x = screen.frame.midX - frame.width / 2
        let y = visibleFrame.maxY - frame.height
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Update panel size and reposition.
    func updateSize(width: CGFloat, height: CGFloat) {
        let menuBarBottom = NSScreen.main?.visibleFrame.maxY ?? frame.origin.y
        let newX = (NSScreen.main?.frame.midX ?? frame.origin.x) - width / 2
        let newY = menuBarBottom - height
        setFrame(
            NSRect(x: newX, y: newY, width: width, height: height),
            display: true,
            animate: true
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
