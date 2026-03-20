import AppKit

struct TerminalLinker {
    private static let terminalBundleIds = [
        "com.cmuxterm.app",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.google.android.studio",
    ]

    static func activate(_ agent: Agent) {
        let pid = Int32(agent.pid)
        DebugLog.shared.log("TerminalLinker: walking process tree from pid \(pid)")

        // Strategy 1: Walk process tree looking for a GUI app ancestor
        let guiPids = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        if ProcessTree.findAncestor(of: pid, where: { guiPids.contains($0) }) != nil {
            TabSelector.activateTab(for: agent)
            return
        }

        DebugLog.shared.log("TerminalLinker: no GUI ancestor found, trying fallback")

        let runningApps = NSWorkspace.shared.runningApplications

        // Strategy 2: Try bundle-specific selection without ancestry.
        // OpenCode sessions can be detached from the terminal process tree,
        // but Ghostty still lets us select tabs by working directory.
        if let cwd = agent.cwd,
           let ghostty = runningApps.first(where: { $0.bundleIdentifier == GhosttyLinker.bundleId }) {
            Task {
                let selected = await GhosttyLinker.selectTab(cwd: cwd, title: agent.sessionTitle)
                if !selected {
                    DebugLog.shared.log("TerminalLinker: Ghostty fallback tab selection failed")
                    ghostty.unhide()
                    ghostty.activate()
                }
            }
            return
        }

        // Strategy 3: Find a running terminal app and activate it
        for bundleId in terminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                DebugLog.shared.log("  activating terminal: \(bundleId)")
                app.unhide()
                app.activate()
                return
            }
        }

        DebugLog.shared.log("TerminalLinker: no terminal app found")
    }
}
