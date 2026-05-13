import AppKit

/// Resolves the host application for an agent process and provides its icon.
enum HostAppResolver {
    struct HostApp {
        let bundleId: String
        let icon: NSImage
    }

    private static let desktopBundleId = "com.anthropic.claudefordesktop"

    /// Apps that get an icon badge but use a non-editor linker for deep linking.
    private static let iconOnlyBundleIds = [
        "com.google.android.studio",
    ]

    /// Returns the host app for an agent, or nil if it's running in a plain terminal.
    static func resolve(agent: Agent) -> HostApp? {
        // Superset v2 spawns agents from a background host-service process whose
        // PID is not exposed via NSWorkspace.runningApplications, so process-tree
        // walking won't find Superset.app as an ancestor. Trust the env-var-derived
        // workspace ID instead.
        if agent.isSupersetSession, let app = icon(for: SupersetLinker.bundleId) {
            return app
        }

        let pid32 = Int32(agent.pid)
        let runningApps = NSWorkspace.shared.runningApplications

        // Check Claude Desktop
        if let result = findAncestorApp(pid: pid32, bundleId: desktopBundleId, in: runningApps) {
            return result
        }

        // Check editors with URL-scheme deep linking
        for editor in EditorLinker.knownEditors {
            if let result = findAncestorApp(pid: pid32, bundleId: editor.bundleId, in: runningApps) {
                return result
            }
        }

        // Check icon-only apps (no URL-scheme deep linking)
        for bundleId in iconOnlyBundleIds {
            if let result = findAncestorApp(pid: pid32, bundleId: bundleId, in: runningApps) {
                return result
            }
        }

        return nil
    }

    private static func icon(for bundleId: String) -> HostApp? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }), let icon = app.icon else {
            return nil
        }
        return HostApp(bundleId: bundleId, icon: icon)
    }

    private static func findAncestorApp(pid: Int32, bundleId: String, in runningApps: [NSRunningApplication]) -> HostApp? {
        let pids = Set(
            runningApps
                .filter { $0.bundleIdentifier == bundleId }
                .map { $0.processIdentifier }
        )
        guard !pids.isEmpty else {
            return nil
        }
        guard ProcessTree.findAncestor(of: pid, where: { pids.contains($0) }) != nil else {
            return nil
        }
        guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }),
              let icon = app.icon else {
            DebugLog.shared.log("HostAppResolver: \(bundleId) found as ancestor but no icon available")
            return nil
        }
        DebugLog.shared.log("HostAppResolver: resolved pid \(pid) → \(bundleId)")
        return HostApp(bundleId: bundleId, icon: icon)
    }
}
