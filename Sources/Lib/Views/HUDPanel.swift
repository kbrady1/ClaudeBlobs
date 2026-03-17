import AppKit
import SwiftUI

/// Non-activating floating panel that sits just below the menu bar.
/// Fixed size — SwiftUI handles all visual transitions internally.
final class HUDPanel: NSPanel {
    static let panelWidth: CGFloat = 960
    static let panelHeight: CGFloat = 160

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

    /// The primary screen (the one with the menu bar). NSScreen.screens.first is
    /// always the primary display, unlike NSScreen.main which follows keyboard focus.
    private var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    /// Position the panel centered horizontally, top edge at the top of the screen.
    func positionAtTop() {
        guard let screen = primaryScreen else { return }
        let x = screen.frame.midX - frame.width / 2
        let y = screen.frame.maxY - frame.height
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
