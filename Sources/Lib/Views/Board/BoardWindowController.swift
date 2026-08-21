import AppKit
import SwiftUI

final class BoardWindowController: NSObject, NSWindowDelegate {
    let viewModel: BoardViewModel
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    var isOpen: Bool { window?.isVisible ?? false }

    init(viewModel: BoardViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.onClose = { [weak self] in self?.close() }
        viewModel.onOpenAgent = { [weak self] agent in
            if self?.viewModel.closesAfterDeepLink == true {
                self?.close(restoreFocus: false)
            }
            DeepLinker.open(agent)
        }
    }

    func open() {
        if isOpen, let window {
            bringToFront(window)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let window = self.window ?? makeWindow()
        self.window = window
        viewModel.closeOverlays()
        viewModel.resetSelection()
        viewModel.syncConductorFocus()
        bringToFront(window)
        installKeyMonitor()
    }

    /// `.regular` only while open (Dock, ⌘-Tab). Activating in the same run-loop turn as the policy switch leaves the previous app in front.
    private func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Pass `restoreFocus: false` when a deep link follows, so focus restore does not race its activation.
    func close(restoreFocus: Bool = true) {
        removeKeyMonitor()
        viewModel.closeOverlays()
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        if restoreFocus {
            previousApp?.activate()
        }
        previousApp = nil
    }

    private func makeWindow() -> NSWindow {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1480, screenFrame.width - 80)
        let height = min(920, screenFrame.height - 80)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Blob Board"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 500)
        window.backgroundColor = NSColor(white: 0.07, alpha: 1)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.setFrameAutosaveName("BlobBoardWindow")
        if !window.setFrameUsingName("BlobBoardWindow") { window.center() }
        let root = BoardView(
            viewModel: viewModel,
            store: viewModel.store,
            tagStore: viewModel.tagStore,
            themeConfig: viewModel.themeConfig
        )
        window.contentView = NSHostingView(rootView: root)
        return window
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible,
                  let eventWindow = event.window, self.belongsToBoard(eventWindow, board: window) else {
                return event
            }
            // Sheets (the tag manager) own their own keyboard handling.
            if window.attachedSheet != nil { return event }
            let textView = eventWindow.firstResponder as? NSTextView
            // Esc in a text field ends editing so the board's keys work again.
            if textView != nil, event.keyCode == 53 {
                eventWindow.makeFirstResponder(nil)
                return nil
            }
            // An empty editor yields arrows and Return to the board.
            let navigationKeys: Set<UInt16> = [36, 123, 124, 125, 126]
            let editing = textView.map { !($0.string.isEmpty && navigationKeys.contains(event.keyCode)) } ?? false
            return self.viewModel.handleKey(event, isEditingText: editing) ? nil : event
        }
    }

    /// Popovers are child windows of the board.
    private func belongsToBoard(_ candidate: NSWindow, board: NSWindow) -> Bool {
        if candidate === board { return true }
        var current: NSWindow? = candidate
        while let parent = current?.parent {
            if parent === board { return true }
            current = parent
        }
        return board.childWindows?.contains(candidate) ?? false
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        close()
    }
}
