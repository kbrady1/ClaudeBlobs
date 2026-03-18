import AppKit

struct EditorLinker {
    struct EditorInfo {
        let bundleId: String
        let urlScheme: String
    }

    static let knownEditors: [EditorInfo] = [
        EditorInfo(bundleId: "com.microsoft.VSCode", urlScheme: "vscode"),
        EditorInfo(bundleId: "com.microsoft.VSCodeInsiders", urlScheme: "vscode-insiders"),
        EditorInfo(bundleId: "com.todesktop.230313mzl4w4u92", urlScheme: "cursor"),
    ]

    /// Check if the agent process is a descendant of a known editor.
    static func findEditorAncestor(pid: Int32) -> EditorInfo? {
        let runningApps = NSWorkspace.shared.runningApplications
        for editor in knownEditors {
            let pids = Set(
                runningApps
                    .filter { $0.bundleIdentifier == editor.bundleId }
                    .map { $0.processIdentifier }
            )
            guard !pids.isEmpty else { continue }
            if ProcessTree.findAncestor(of: pid, where: { pids.contains($0) }) != nil {
                return editor
            }
        }
        return nil
    }

    static func activate(_ agent: Agent, editor: EditorInfo) {
        // Use URL scheme to focus the workspace folder in the editor
        if let cwd = agent.cwd,
           let url = URL(string: "\(editor.urlScheme)://file\(cwd)") {
            NSWorkspace.shared.open(url)
            DebugLog.shared.log("EditorLinker: opened \(url)")
            return
        }

        // Fallback: just activate the editor app
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == editor.bundleId }) {
            app.unhide()
            app.activate()
            DebugLog.shared.log("EditorLinker: activated \(editor.bundleId)")
        }
    }
}
