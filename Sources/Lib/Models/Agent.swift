import Foundation

struct Agent: Codable, Identifiable, Equatable, Sendable {
    let sessionId: String
    let pid: Int
    let cwd: String?
    var agentType: String?
    var status: AgentStatus
    var lastMessage: String?
    var lastToolUse: String?
    var cmuxWorkspace: String?
    var cmuxSurface: String?
    var updatedAt: Int64

    var id: String { sessionId }

    var directoryLabel: String {
        if let agentType { return agentType }
        guard let cwd else { return "APP" }
        return (cwd as NSString).lastPathComponent
    }

    var speechBubbleText: String {
        switch status {
        case .waiting:
            return lastMessage ?? ""
        case .working:
            return lastToolUse ?? ""
        case .permission:
            if let tool = lastToolUse {
                return "Wants to run: \(tool)"
            }
            return ""
        case .starting:
            return "Starting up..."
        }
    }

    var isCmuxSession: Bool {
        cmuxWorkspace != nil && cmuxSurface != nil
    }
}

extension Agent {
    static func fixture(
        sessionId: String = "test-session",
        pid: Int = 99999,
        cwd: String? = "/tmp/test",
        agentType: String? = nil,
        status: AgentStatus = .working,
        lastMessage: String? = nil,
        lastToolUse: String? = nil,
        cmuxWorkspace: String? = nil,
        cmuxSurface: String? = nil,
        updatedAt: Int64 = 1000
    ) -> Agent {
        Agent(
            sessionId: sessionId, pid: pid, cwd: cwd,
            agentType: agentType, status: status,
            lastMessage: lastMessage, lastToolUse: lastToolUse,
            cmuxWorkspace: cmuxWorkspace, cmuxSurface: cmuxSurface,
            updatedAt: updatedAt
        )
    }
}
