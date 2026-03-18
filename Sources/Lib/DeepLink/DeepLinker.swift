import AppKit

enum LinkType: Equatable {
    case cmux
    case editor
    case terminal
    case desktop
}

struct DeepLinker {
    private static let desktopBundleId = "com.anthropic.claudefordesktop"

    static func linkType(for agent: Agent) -> LinkType {
        if agent.isCmuxSession { return .cmux }
        if isDesktopAgent(pid: Int32(agent.pid)) { return .desktop }
        if EditorLinker.findEditorAncestor(pid: Int32(agent.pid)) != nil { return .editor }
        if agent.cwd != nil { return .terminal }
        return .desktop
    }

    /// Walk the process tree to check if this agent was spawned by Claude Desktop.
    private static func isDesktopAgent(pid: Int32) -> Bool {
        let desktopPids = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == desktopBundleId }
                .map { $0.processIdentifier }
        )
        guard !desktopPids.isEmpty else { return false }
        return ProcessTree.findAncestor(of: pid) { desktopPids.contains($0) } != nil
    }

    static func open(_ agent: Agent) {
        let type = linkType(for: agent)
        DebugLog.shared.log("DeepLinker.open: sessionId=\(agent.sessionId) linkType=\(type) pid=\(agent.pid) cwd=\(agent.cwd ?? "nil") cmuxWs=\(agent.cmuxWorkspace ?? "nil") cmuxSf=\(agent.cmuxSurface ?? "nil")")

        switch type {
        case .cmux:
            CmuxLinker.activate(agent)
        case .editor:
            if let editor = EditorLinker.findEditorAncestor(pid: Int32(agent.pid)) {
                EditorLinker.activate(agent, editor: editor)
            }
        case .terminal:
            TerminalLinker.activate(agent)
        case .desktop:
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == desktopBundleId }) {
                app.unhide()
                app.activate()
                DebugLog.shared.log("DeepLinker: activated running Claude Desktop")
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                DebugLog.shared.log("DeepLinker: launched Claude Desktop at \(url)")
            } else {
                DebugLog.shared.log("DeepLinker: Claude Desktop not found")
            }
        }
    }
}
