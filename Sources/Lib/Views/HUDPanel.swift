import AppKit
import SwiftUI

/// Non-activating floating panel that sits just below the menu bar.
/// Fixed width; height is single-row by default and grows to fit overflow
/// rows when the expanded view wraps (see `setRowCount`). SwiftUI handles the
/// collapsed/expanded visual transitions internally.
final class HUDPanel: NSPanel {
    static let panelWidth: CGFloat = 960
    /// Default (single-row) height. The panel grows taller when the expanded
    /// view wraps overflow agents onto additional rows; see `setRowCount`.
    static let panelHeight: CGFloat = 160
    /// Height of each additional row of agent cards beyond the first.
    static let rowHeight: CGFloat = 110

    /// Number of card rows the expanded view is currently showing. Driving the
    /// panel height off this keeps the transparent panel as small as possible so
    /// it doesn't block clicks/hover to apps beneath the empty region.
    private var rowCount: Int = 1

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

    /// Screen this panel is placed on, retained so the panel can re-layout when
    /// its row count changes without the caller re-supplying the screen.
    private weak var placementScreen: NSScreen?

    /// Position the panel centered horizontally at the very top of the screen.
    /// On notched displays the panel extends behind the notch area so the
    /// expanded background can fill up to the screen edge.
    func positionAtTop(of screen: NSScreen) {
        placementScreen = screen
        notchInset = screen.safeAreaInsets.top
        layout(on: screen)
    }

    /// Grow or shrink the panel to fit `rows` rows of cards. The top edge stays
    /// pinned to the screen top; only the bottom edge moves. Keeping the panel
    /// no taller than needed prevents the transparent area from swallowing
    /// clicks/hover meant for apps beneath it.
    func setRowCount(_ rows: Int) {
        let clamped = max(1, rows)
        guard clamped != rowCount else { return }
        rowCount = clamped
        if let screen = placementScreen {
            layout(on: screen, animated: true)
        }
    }

    private var contentHeight: CGFloat {
        Self.panelHeight + CGFloat(rowCount - 1) * Self.rowHeight
    }

    private func layout(on screen: NSScreen, animated: Bool = false) {
        let totalHeight = contentHeight + notchInset
        let x = screen.frame.midX - Self.panelWidth / 2
        let y = screen.frame.maxY - totalHeight
        let frame = NSRect(x: x, y: y, width: Self.panelWidth, height: totalHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
