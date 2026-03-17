import Foundation

enum AgentStaleness: Sendable, Equatable {
    case active
    case stale   // >20 min since last update
    case hung    // >1 hr since last update

    init(updatedAt: Int64) {
        let ageSeconds = (Int64(Date().timeIntervalSince1970 * 1000) - updatedAt) / 1000
        if ageSeconds > 3600 { self = .hung }
        else if ageSeconds > 1200 { self = .stale }
        else { self = .active }
    }
}

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
    var cmuxSocketPath: String?
    var parentSessionId: String?
    var waitReason: String?
    var taskCompletedAt: Int64?
    var createdAt: Int64?
    var updatedAt: Int64

    var id: String { sessionId }

    /// Whether the agent is done (vs asking a follow-up question) when waiting.
    var isDone: Bool { waitReason == "done" }

    /// Whether the last tool use was a coding tool (Edit, Write, Bash, etc.)
    var isCoding: Bool {
        guard let tool = lastToolUse else { return false }
        let codingPrefixes = ["Edit", "Write", "Bash", "NotebookEdit"]
        return codingPrefixes.contains { tool.hasPrefix($0) }
    }

    /// Whether the last tool use was a web tool (WebSearch, WebFetch).
    var isSearching: Bool {
        guard let tool = lastToolUse else { return false }
        let webPrefixes = ["WebSearch", "WebFetch"]
        return webPrefixes.contains { tool.hasPrefix($0) }
    }

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
        case .compacting:
            return "Compacting context..."
        }
    }

    var isCmuxSession: Bool {
        cmuxWorkspace != nil && cmuxSurface != nil
    }

    var staleness: AgentStaleness {
        AgentStaleness(updatedAt: updatedAt)
    }

    var isTaskJustCompleted: Bool {
        guard let ts = taskCompletedAt else { return false }
        let ageMs = Int64(Date().timeIntervalSince1970 * 1000) - ts
        return ageMs >= 0 && ageMs < 3000
    }

    /// Whether this is a plan approval permission (ExitPlanMode) vs a dangerous tool permission.
    var isPlanApproval: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("ExitPlanMode")
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
        cmuxSocketPath: String? = nil,
        parentSessionId: String? = nil,
        waitReason: String? = nil,
        taskCompletedAt: Int64? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64 = 1000
    ) -> Agent {
        Agent(
            sessionId: sessionId, pid: pid, cwd: cwd,
            agentType: agentType, status: status,
            lastMessage: lastMessage, lastToolUse: lastToolUse,
            cmuxWorkspace: cmuxWorkspace, cmuxSurface: cmuxSurface,
            cmuxSocketPath: cmuxSocketPath, parentSessionId: parentSessionId,
            waitReason: waitReason, taskCompletedAt: taskCompletedAt,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
