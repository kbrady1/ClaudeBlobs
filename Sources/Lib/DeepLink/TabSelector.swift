import AppKit

/// Shared logic for selecting a terminal tab by TTY and activating the host app.
enum TabSelector {
    /// Attempts to select the terminal tab matching the agent's TTY in its host terminal.
    /// Falls back to simply activating the host app if tab selection isn't possible.
    static func activateTab(for agent: Agent) {
        let pid = Int32(agent.pid)
        let tty = agent.tty ?? ProcessTree.resolveTTY(of: pid)

        // Find the GUI app ancestor (the terminal hosting this agent)
        let guiPids = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        guard let ancestorPid = ProcessTree.findAncestor(of: pid, where: { guiPids.contains($0) }),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == ancestorPid }) else {
            DebugLog.shared.log("TabSelector: no GUI ancestor for pid \(pid)")
            return
        }

        let bundleId = app.bundleIdentifier ?? "unknown"
        DebugLog.shared.log("TabSelector: host app=\(bundleId) tty=\(tty ?? "nil") pid=\(pid)")

        // Ghostty matches by cwd (no TTY in its scripting dictionary)
        if bundleId == GhosttyLinker.bundleId, let cwd = agent.cwd {
            Task {
                let selected = await GhosttyLinker.selectTab(cwd: cwd, title: agent.sessionTitle)
                if !selected {
                    DebugLog.shared.log("TabSelector: Ghostty tab selection failed, falling back to activate")
                    app.unhide()
                    app.activate()
                }
            }
            return
        }

        if let tty {
            if bundleId == ITermLinker.bundleId {
                Task {
                    let selected = await ITermLinker.selectTab(tty: tty)
                    if !selected {
                        DebugLog.shared.log("TabSelector: iTerm2 tab selection failed, falling back to activate")
                        app.unhide()
                        app.activate()
                    }
                }
                return
            } else if bundleId == TerminalAppLinker.bundleId {
                Task {
                    let selected = await TerminalAppLinker.selectTab(tty: tty)
                    if !selected {
                        DebugLog.shared.log("TabSelector: Terminal.app tab selection failed, falling back to activate")
                        app.unhide()
                        app.activate()
                    }
                }
                return
            }
        }

        app.unhide()
        app.activate()
    }
}
