import AppKit
import SwiftUI
import Combine
import ServiceManagement

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: HUDPanel!
    private var store: AgentStore!
    private var cancellables = Set<AnyCancellable>()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = AgentStore()
        panel = HUDPanel()

        let contentView = HUDContentView(store: store) { agent in
            DeepLinker.open(agent)
        }

        panel.contentView = NSHostingView(rootView: contentView)
        panel.positionBelowMenuBar()

        // Show/hide based on agent count
        store.$agents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in
                guard let self else { return }
                if agents.isEmpty {
                    self.panel.orderOut(nil)
                } else {
                    self.panel.orderFront(nil)
                    self.panel.positionBelowMenuBar()
                }
                self.updatePanelSize()
            }
            .store(in: &cancellables)

        // Listen for expansion changes to resize panel
        NotificationCenter.default.publisher(for: .hudExpansionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)

        // Right-click context menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Reinstall Hooks", action: #selector(reinstallHooks), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Uninstall Hooks & Quit", action: #selector(uninstallAndQuit), keyEquivalent: "")
        panel.menu = menu

        // First launch: confirm and install hooks
        if !UserDefaults.standard.bool(forKey: "hooksInstalled") {
            let confirm = NSAlert()
            confirm.messageText = "Set up Claude Agent HUD?"
            confirm.informativeText = "This will install hooks into your Claude Code settings to track agent status. You can uninstall later via right-click on the HUD."
            confirm.addButton(withTitle: "Continue")
            confirm.addButton(withTitle: "Quit")

            if confirm.runModal() == .alertSecondButtonReturn {
                NSApp.terminate(nil)
                return
            }

            do {
                try HookInstaller().install()
                try FileManager.default.createDirectory(
                    at: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".claude/agent-status"),
                    withIntermediateDirectories: true
                )
                UserDefaults.standard.set(true, forKey: "hooksInstalled")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to install hooks"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }

        // Register as login item
        try? SMAppService.mainApp.register()
    }

    private func updatePanelSize() {
        let agentCount = max(store.agents.count, store.collapsedAgents.count)
        if agentCount == 0 { return }

        let isExpanded = panel.contentView?.frame.height ?? 0 > 30
        if isExpanded {
            let width = CGFloat(min(agentCount, 10)) * 92 + 24
            panel.updateSize(width: width, height: 120)
        } else {
            let collapsedCount = store.collapsedAgents.count
            let width = CGFloat(min(collapsedCount, 10)) * 26 + 24
            panel.updateSize(width: width, height: 22)
        }
    }

    @objc private func reinstallHooks() {
        do {
            try HookInstaller().install()
            let alert = NSAlert()
            alert.messageText = "Hooks reinstalled"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to reinstall hooks"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func uninstallAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Claude Agent HUD?"
        alert.informativeText = "This will remove hooks from Claude Code settings and delete status files."
        alert.addButton(withTitle: "Uninstall & Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            try? Uninstaller().uninstall()
            UserDefaults.standard.removeObject(forKey: "hooksInstalled")
            NSApp.terminate(nil)
        }
    }
}
