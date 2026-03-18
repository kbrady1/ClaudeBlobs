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

        // Strategy 2: Find a running terminal app and activate it
        let runningApps = NSWorkspace.shared.runningApplications
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
