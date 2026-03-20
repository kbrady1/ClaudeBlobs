import AppKit
import Carbon.HIToolbox
import SwiftUI
import Combine
import ServiceManagement

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [HUDPanel] = []
    private var store: AgentStore!
    private var expansionState: HUDExpansionState!
    private var ntfyConfig: NtfyConfig!
    private var themeConfig: ThemeConfig!
    private var ntfyScheduler: NtfyScheduler!
    private var statusItem: NSStatusItem!
    private var debugMenuItem: NSMenuItem!
    private var ntfyMenuItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var themeWindow: NSWindow?
    private var hotkeyWindow: NSWindow?
    private var hotkeyConfig: HotkeyConfig!
    private var hotkeyMenuItem: NSMenuItem!
    private var eventHandlerInstalled = false
    private var cancellables = Set<AnyCancellable>()
    private var hideWhileCollapsedMenuItem: NSMenuItem!
    private var hideWorkingMenuItem: NSMenuItem!
    private var sortByPriorityMenuItem: NSMenuItem!
    private var viewLogMenuItem: NSMenuItem!
    private var clearLogMenuItem: NSMenuItem!
    private var hotkeyRef: EventHotKeyRef?
    private var globalHotkeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var previousApp: NSRunningApplication?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = AgentStore()
        expansionState = HUDExpansionState()
        ntfyConfig = NtfyConfig()
        themeConfig = ThemeConfig()
        ntfyScheduler = NtfyScheduler(config: ntfyConfig)
        store.ntfyScheduler = ntfyScheduler
        rebuildPanels()

        // Rebuild panels when screen placement preference changes
        store.$screenPlacement
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildPanels() }
            .store(in: &cancellables)

        // Rebuild when monitor arrangement changes (e.g. plugging/unplugging displays)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildPanels() }
            .store(in: &cancellables)

        // Show/hide based on agent count
        store.$agents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in
                guard let self else { return }
                for panel in self.panels {
                    if agents.isEmpty {
                        panel.orderOut(nil)
                    } else {
                        panel.orderFront(nil)
                    }
                }
            }
            .store(in: &cancellables)

        // Menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.create(size: 18)
        }

        let menu = NSMenu()

        let agentDisplayMenu = NSMenu()

        hideWhileCollapsedMenuItem = NSMenuItem(title: "Hide While Collapsed", action: #selector(toggleHideWhileCollapsed), keyEquivalent: "h")
        hideWhileCollapsedMenuItem.target = self
        hideWhileCollapsedMenuItem.state = store.hideWhileCollapsed ? .on : .off
        agentDisplayMenu.addItem(hideWhileCollapsedMenuItem)

        hideWorkingMenuItem = NSMenuItem(title: "Hide Working Agents", action: #selector(toggleHideWorking), keyEquivalent: "a")
        hideWorkingMenuItem.target = self
        hideWorkingMenuItem.state = store.hideWorkingAgents ? .on : .off
        agentDisplayMenu.addItem(hideWorkingMenuItem)

        sortByPriorityMenuItem = NSMenuItem(title: "Sort by Priority", action: #selector(toggleSortByPriority), keyEquivalent: "")
        sortByPriorityMenuItem.target = self
        sortByPriorityMenuItem.state = store.sortByPriority ? .on : .off
        agentDisplayMenu.addItem(sortByPriorityMenuItem)

        agentDisplayMenu.addItem(.separator())

        let appIconSubmenu = NSMenu()
        for option in AppIconVisibility.allCases {
            let item = NSMenuItem(title: option.menuTitle, action: #selector(setAppIconVisibility(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = store.appIconVisibility == option ? .on : .off
            appIconSubmenu.addItem(item)
        }
        let appIconMenuItem = NSMenuItem(title: "Show App Icons", action: nil, keyEquivalent: "")
        appIconMenuItem.submenu = appIconSubmenu
        agentDisplayMenu.addItem(appIconMenuItem)

        agentDisplayMenu.addItem(.separator())

        let themeSettingsItem = NSMenuItem(title: "Theme Settings\u{2026}", action: #selector(openThemeSettings), keyEquivalent: "")
        themeSettingsItem.target = self
        agentDisplayMenu.addItem(themeSettingsItem)

        let agentDisplayMenuItem = NSMenuItem(title: "Blob Settings", action: nil, keyEquivalent: "")
        agentDisplayMenuItem.submenu = agentDisplayMenu
        menu.addItem(agentDisplayMenuItem)

        let screenMenu = NSMenu()
        for option in ScreenPlacement.allCases {
            let item = NSMenuItem(title: option.menuTitle, action: #selector(setScreenPlacement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = store.screenPlacement == option ? .on : .off
            screenMenu.addItem(item)
        }
        let screenMenuItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        screenMenuItem.submenu = screenMenu
        menu.addItem(screenMenuItem)

        menu.addItem(.separator())

        ntfyMenuItem = NSMenuItem(title: "Push Notifications", action: #selector(toggleNtfy), keyEquivalent: "n")
        ntfyMenuItem.target = self
        ntfyMenuItem.state = ntfyConfig.isEnabled ? .on : .off
        menu.addItem(ntfyMenuItem)

        let ntfySettingsItem = NSMenuItem(title: "Notification Settings\u{2026}", action: #selector(openNtfySettings), keyEquivalent: "")
        ntfySettingsItem.target = self
        menu.addItem(ntfySettingsItem)

        menu.addItem(.separator())

        hotkeyConfig = HotkeyConfig.load()
        hotkeyMenuItem = NSMenuItem(title: "Hotkey: \(hotkeyConfig.displayString)", action: nil, keyEquivalent: "")
        hotkeyMenuItem.isEnabled = false
        menu.addItem(hotkeyMenuItem)

        let changeHotkeyItem = NSMenuItem(title: "Change Hotkey\u{2026}", action: #selector(openHotkeySettings), keyEquivalent: "")
        changeHotkeyItem.target = self
        menu.addItem(changeHotkeyItem)

        menu.addItem(.separator())

        debugMenuItem = NSMenuItem(title: "Debug Mode", action: #selector(toggleDebug), keyEquivalent: "d")
        debugMenuItem.target = self
        debugMenuItem.state = DebugLog.shared.isEnabled ? .on : .off
        menu.addItem(debugMenuItem)

        viewLogMenuItem = NSMenuItem(title: "Open Debug Log", action: #selector(openDebugLog), keyEquivalent: "")
        viewLogMenuItem.target = self
        viewLogMenuItem.isHidden = !DebugLog.shared.isEnabled
        menu.addItem(viewLogMenuItem)

        clearLogMenuItem = NSMenuItem(title: "Clear Debug Log", action: #selector(clearDebugLog), keyEquivalent: "")
        clearLogMenuItem.target = self
        clearLogMenuItem.isHidden = !DebugLog.shared.isEnabled
        menu.addItem(clearLogMenuItem)

        let reinstallItem = NSMenuItem(title: "Reinstall Claude Code Hooks", action: #selector(reinstallHooks), keyEquivalent: "")
        reinstallItem.target = self
        menu.addItem(reinstallItem)

        let openCodeItem = NSMenuItem(title: "Reinstall OpenCode Plugin", action: #selector(installOpenCodePlugin), keyEquivalent: "")
        openCodeItem.target = self
        menu.addItem(openCodeItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall Hooks & Quit", action: #selector(uninstallAndQuit), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        statusItem.menu = menu

        // First launch: confirm and install hooks
        if !UserDefaults.standard.bool(forKey: "hooksInstalled") {
            let confirm = NSAlert()
            confirm.messageText = "Set up ClaudeBlobs?"
            confirm.informativeText = "This will install Claude Code hooks and the bundled OpenCode plugin so ClaudeBlobs can track both providers. You can uninstall later from the menu bar icon."
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
                try OpenCodeInstaller().install()
                UserDefaults.standard.set(true, forKey: "hooksInstalled")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to install ClaudeBlobs integrations"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }

        if UserDefaults.standard.bool(forKey: "hooksInstalled") {
            try? OpenCodeInstaller().install()
        }

        // Register as login item
        try? SMAppService.mainApp.register()

        // Register global hotkey ⌃⌥A via Carbon (no Accessibility permission needed)
        registerGlobalHotkey()

        // Global monitor for 1-9 and Escape when picker is open (needs Accessibility)
        // Also register local monitor as fallback when our app is active
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handlePickerKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePickerKeyEvent(event) ? nil : event
        }

        // Set dock/app icon programmatically
        NSApp.applicationIconImage = AppIcon.create(size: 512)

        DebugLog.shared.log("App launched. Debug mode is ON.")
    }

    private func registerGlobalHotkey() {
        // Unregister previous hotkey if re-registering
        if let existing = hotkeyRef {
            UnregisterEventHotKey(existing)
            hotkeyRef = nil
        }

        let config = hotkeyConfig ?? .default

        // Install the Carbon event handler only once
        if !eventHandlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.togglePicker()
                }
                return noErr
            }, 1, &eventType, selfPtr, nil)
            eventHandlerInstalled = true
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x48554430) // "HUD0"
        hotKeyID.id = 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(config.keyCode, config.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotkeyRef = ref
            DebugLog.shared.log("Registered global hotkey \(config.displayString)")
        } else {
            DebugLog.shared.log("Failed to register global hotkey: \(status)")
        }
    }

    private func togglePicker() {
        if expansionState.isKeyboardExpanded {
            closePicker()
        } else {
            guard !store.agents.isEmpty else { return }
            // Remember the currently focused app so we can restore it
            previousApp = NSWorkspace.shared.frontmostApplication
            if let keyPanel = panels.first {
                keyPanel.orderFront(nil)
                keyPanel.makeKey()
            }
            NSApp.activate(ignoringOtherApps: true)
            expansionState.toggle(agentCount: store.agents.count)
        }
    }

    private func closePicker() {
        expansionState.collapse()
        // Restore focus to the previously active app
        previousApp?.activate()
        previousApp = nil
    }

    /// Tear down existing panels and create one per target screen.
    private func rebuildPanels() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()

        let contentView = HUDContentView(store: store, expansionState: expansionState, ntfyScheduler: ntfyScheduler, themeConfig: themeConfig) { agent in
            DebugLog.shared.log("Agent clicked: \(agent.sessionId)")
            DeepLinker.open(agent)
        }

        for screen in screensForPlacement() {
            let panel = HUDPanel()
            panel.positionAtTop(of: screen)
            let view = contentView.environment(\.notchInset, panel.notchInset)
            panel.contentView = NSHostingView(rootView: view)
            if !store.agents.isEmpty {
                panel.orderFront(nil)
            }
            panels.append(panel)
        }
    }

    private func screensForPlacement() -> [NSScreen] {
        let screens = NSScreen.screens
        switch store.screenPlacement {
        case .allDisplays:
            return screens
        case .primaryOnly:
            return screens.first.map { [$0] } ?? []
        case .allExceptPrimary:
            return Array(screens.dropFirst())
        }
    }

    /// Handle Tab, Shift+Tab, Enter, and Escape when picker is open. Returns true if handled.
    @discardableResult
    private func handlePickerKeyEvent(_ event: NSEvent) -> Bool {
        guard expansionState.isKeyboardExpanded else { return false }
        let agentCount = min(store.sortedTopLevelAgents.count, 9)

        // Escape — close picker
        if event.keyCode == 53 {
            DispatchQueue.main.async { self.closePicker() }
            return true
        }

        // Tab / Shift+Tab — cycle selection
        if event.keyCode == 48 { // Tab
            DispatchQueue.main.async {
                if event.modifierFlags.contains(.shift) {
                    self.expansionState.cycleBackward(agentCount: agentCount)
                } else {
                    self.expansionState.cycleForward(agentCount: agentCount)
                }
            }
            return true
        }

        // Left arrow — cycle backward
        if event.keyCode == 123 {
            DispatchQueue.main.async {
                self.expansionState.cycleBackward(agentCount: agentCount)
            }
            return true
        }

        // Right arrow — cycle forward
        if event.keyCode == 124 {
            DispatchQueue.main.async {
                self.expansionState.cycleForward(agentCount: agentCount)
            }
            return true
        }

        // Enter — open selected agent
        if event.keyCode == 36 {
            let index = expansionState.selectedIndex
            let agents = store.sortedTopLevelAgents
            if index < agents.count {
                DispatchQueue.main.async {
                    DebugLog.shared.log("Hotkey select agent \(index): \(agents[index].sessionId)")
                    self.closePicker()
                    DeepLinker.open(agents[index])
                }
            }
            return true
        }

        // Delete/Backspace — snooze or dismiss selected agent
        if event.keyCode == 51 {
            let index = expansionState.selectedIndex
            let agents = store.sortedTopLevelAgents
            if index < agents.count {
                let agent = agents[index]
                DispatchQueue.main.async {
                    if self.store.snoozedSessionIds.contains(agent.id) {
                        DebugLog.shared.log("Hotkey dismiss agent \(index): \(agent.sessionId)")
                        self.store.dismiss(agent)
                    } else {
                        DebugLog.shared.log("Hotkey snooze agent \(index): \(agent.sessionId)")
                        self.store.snooze(agent)
                    }
                }
            }
            return true
        }

        return false
    }

    @objc private func toggleNtfy() {
        ntfyConfig.isEnabled.toggle()
        ntfyMenuItem.state = ntfyConfig.isEnabled ? .on : .off
        if !ntfyConfig.isEnabled {
            ntfyScheduler.cancelAll()
        }
    }

    @objc private func openNtfySettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notification Settings"
        window.contentView = NSHostingView(rootView: NtfySettingsView(config: ntfyConfig))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func openThemeSettings() {
        if let existing = themeWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Theme Settings"
        window.contentView = NSHostingView(rootView: ThemeSettingsView(config: themeConfig))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        themeWindow = window
    }

    @objc private func openHotkeySettings() {
        if let existing = hotkeyWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = HotkeyRecorderView(config: Binding(
            get: { [weak self] in self?.hotkeyConfig ?? .default },
            set: { [weak self] newValue in self?.hotkeyConfig = newValue }
        )) { [weak self] in
            guard let self else { return }
            self.hotkeyMenuItem.title = "Hotkey: \(self.hotkeyConfig.displayString)"
            self.registerGlobalHotkey()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Change Hotkey"
        window.contentView = NSHostingView(rootView: view.padding())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hotkeyWindow = window
    }

    @objc private func toggleHideWhileCollapsed() {
        store.hideWhileCollapsed.toggle()
        hideWhileCollapsedMenuItem.state = store.hideWhileCollapsed ? .on : .off
    }

    @objc private func clearAgents() {
        store.dismissAll()
    }

    @objc private func toggleHideWorking() {
        store.hideWorkingAgents.toggle()
        hideWorkingMenuItem.state = store.hideWorkingAgents ? .on : .off
    }

    @objc private func toggleSortByPriority() {
        store.sortByPriority.toggle()
        sortByPriorityMenuItem.state = store.sortByPriority ? .on : .off
    }

    @objc private func setAppIconVisibility(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = AppIconVisibility(rawValue: raw) else { return }
        store.appIconVisibility = option
        // Update checkmarks in the submenu
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = item.representedObject as? String == raw ? .on : .off
            }
        }
    }

    @objc private func setScreenPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = ScreenPlacement(rawValue: raw) else { return }
        store.screenPlacement = option
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = item.representedObject as? String == raw ? .on : .off
            }
        }
    }

    @objc private func toggleDebug() {
        DebugLog.shared.isEnabled.toggle()
        debugMenuItem.state = DebugLog.shared.isEnabled ? .on : .off
        viewLogMenuItem.isHidden = !DebugLog.shared.isEnabled
        clearLogMenuItem.isHidden = !DebugLog.shared.isEnabled
        DebugLog.shared.log("Debug mode toggled ON")
    }

    @objc private func openDebugLog() {
        let logPath = NSHomeDirectory() + "/Library/Logs/ClaudeBlobs/debug.log"
        if FileManager.default.fileExists(atPath: logPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        } else {
            let alert = NSAlert()
            alert.messageText = "No debug log found"
            alert.informativeText = "Enable debug mode and interact with the HUD to generate log entries."
            alert.runModal()
        }
    }

    @objc private func clearDebugLog() {
        DebugLog.shared.clear()
    }

    @objc private func reinstallHooks() {
        do {
            try HookInstaller().install()
            let alert = NSAlert()
            alert.messageText = "Claude Code hooks reinstalled"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to reinstall hooks"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func installOpenCodePlugin() {
        do {
            try OpenCodeInstaller().install()
            let alert = NSAlert()
            alert.messageText = "OpenCode plugin reinstalled"
            alert.informativeText = "ClaudeBlobs will now track your OpenCode sessions. Restart OpenCode if it is already running."
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to reinstall OpenCode plugin"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func uninstallAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Uninstall ClaudeBlobs?"
        alert.informativeText = "This will remove Claude Code hooks, uninstall the OpenCode plugin, and delete status files."
        alert.addButton(withTitle: "Uninstall & Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            try? Uninstaller().uninstall()
            UserDefaults.standard.removeObject(forKey: "hooksInstalled")
            NSApp.terminate(nil)
        }
    }
}
