import AppKit

enum LinkType: Equatable {
    case cmux
    case terminal
    case desktop
}

struct DeepLinker {
    static func linkType(for agent: Agent) -> LinkType {
        if agent.isCmuxSession { return .cmux }
        if agent.cwd != nil { return .terminal }
        return .desktop
    }

    static func open(_ agent: Agent) {
        switch linkType(for: agent) {
        case .cmux:
            CmuxLinker.activate(agent)
        case .terminal:
            TerminalLinker.activate(agent)
        case .desktop:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
        }
    }
}
