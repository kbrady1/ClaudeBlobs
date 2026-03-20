import Foundation

enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case openCode = "opencode"

    var statusDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode:
            return home.appendingPathComponent(".claude/agent-status")
        case .openCode:
            return home.appendingPathComponent(".opencode/agent-status")
        }
    }
}

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
    var provider: AgentProvider
    let sessionId: String
    let pid: Int
    let cwd: String?
    var agentType: String?
    var sessionTitle: String?
    var status: AgentStatus
    var lastMessage: String?
    var lastToolUse: String?
    var tty: String?
    var cmuxWorkspace: String?
    var cmuxSurface: String?
    var cmuxSocketPath: String?
    var parentSessionId: String?
    var waitReason: String?
    var toolFailure: String?
    var taskCompletedAt: Int64?
    var createdAt: Int64?
    var updatedAt: Int64
    var statusChangedAt: Int64?

    var id: String { "\(provider.rawValue):\(sessionId)" }

    init(
        provider: AgentProvider = .claudeCode,
        sessionId: String,
        pid: Int,
        cwd: String?,
        agentType: String? = nil,
        sessionTitle: String? = nil,
        status: AgentStatus,
        lastMessage: String? = nil,
        lastToolUse: String? = nil,
        tty: String? = nil,
        cmuxWorkspace: String? = nil,
        cmuxSurface: String? = nil,
        cmuxSocketPath: String? = nil,
        parentSessionId: String? = nil,
        waitReason: String? = nil,
        toolFailure: String? = nil,
        taskCompletedAt: Int64? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64,
        statusChangedAt: Int64? = nil
    ) {
        self.provider = provider
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.agentType = agentType
        self.sessionTitle = sessionTitle
        self.status = status
        self.lastMessage = lastMessage
        self.lastToolUse = lastToolUse
        self.tty = tty
        self.cmuxWorkspace = cmuxWorkspace
        self.cmuxSurface = cmuxSurface
        self.cmuxSocketPath = cmuxSocketPath
        self.parentSessionId = parentSessionId
        self.waitReason = waitReason
        self.toolFailure = toolFailure
        self.taskCompletedAt = taskCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statusChangedAt = statusChangedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case sessionId
        case pid
        case cwd
        case agentType
        case sessionTitle
        case status
        case lastMessage
        case lastToolUse
        case tty
        case cmuxWorkspace
        case cmuxSurface
        case cmuxSocketPath
        case parentSessionId
        case waitReason
        case toolFailure
        case taskCompletedAt
        case createdAt
        case updatedAt
        case statusChangedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .claudeCode
        sessionId = try container.decode(String.self, forKey: .sessionId)
        pid = try container.decode(Int.self, forKey: .pid)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        sessionTitle = try container.decodeIfPresent(String.self, forKey: .sessionTitle)
        status = try container.decode(AgentStatus.self, forKey: .status)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastToolUse = try container.decodeIfPresent(String.self, forKey: .lastToolUse)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        cmuxWorkspace = try container.decodeIfPresent(String.self, forKey: .cmuxWorkspace)
        cmuxSurface = try container.decodeIfPresent(String.self, forKey: .cmuxSurface)
        cmuxSocketPath = try container.decodeIfPresent(String.self, forKey: .cmuxSocketPath)
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        waitReason = try container.decodeIfPresent(String.self, forKey: .waitReason)
        toolFailure = try container.decodeIfPresent(String.self, forKey: .toolFailure)
        taskCompletedAt = try container.decodeIfPresent(Int64.self, forKey: .taskCompletedAt)
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        statusChangedAt = try container.decodeIfPresent(Int64.self, forKey: .statusChangedAt)
    }

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

    /// Whether the last tool use is reading or searching code (Read, Grep, Glob, LSP, Agent).
    var isExploring: Bool {
        guard let tool = lastToolUse else { return false }
        let explorePrefixes = ["Read", "Grep", "Glob", "LSP", "Agent"]
        return explorePrefixes.contains { tool.hasPrefix($0) }
    }

    /// Whether the last tool use is a Bash command that looks like running tests or verification.
    var isTesting: Bool {
        guard let tool = lastToolUse else { return false }
        guard tool.hasPrefix("Bash: ") || tool.hasPrefix("Bash:") else { return false }
        let cmd = tool.dropFirst(tool.hasPrefix("Bash: ") ? 6 : 5).lowercased()
        let testPatterns = [
            "test", "spec", "verify", "check", "xcodebuild", "pytest", "jest",
            "mocha", "vitest", "cypress", "playwright", "cargo test", "go test",
            "swift test", "make test", "make check", "lint", "tox", "nox"
        ]
        return testPatterns.contains { cmd.contains($0) }
    }

    /// Whether the last tool use was an MCP tool (mcp__server__tool).
    var isMcpTool: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("mcp__")
    }

    /// Whether the last tool use is a GitHub-related tool (GitHub MCP, git/gh bash commands).
    var isGithubTool: Bool {
        guard let tool = lastToolUse else { return false }
        if tool.hasPrefix("mcp__github__") { return true }
        guard tool.hasPrefix("Bash") else { return false }
        let lower = tool.lowercased()
        let gitPatterns = ["\"git ", "\"gh ", "\"git\t", "\"gh\t"]
        return gitPatterns.contains { lower.contains($0) }
    }

    /// Formats an MCP tool name for display: "mcp__github__create_pr: {...}" → "github: create_pr"
    static func formatMcpToolName(_ raw: String) -> String {
        // Split off the input portion after ": "
        let toolPart: String
        let inputPart: String?
        if let colonRange = raw.range(of: ": ") {
            toolPart = String(raw[raw.startIndex..<colonRange.lowerBound])
            inputPart = String(raw[colonRange.upperBound...])
        } else {
            toolPart = raw
            inputPart = nil
        }
        // Parse mcp__server__toolName
        let segments = toolPart.split(separator: "_", omittingEmptySubsequences: false)
        // Expected: ["mcp", "", "server", "", "tool"]
        // Filter out empty segments from double underscores
        let parts = segments.filter { !$0.isEmpty }
        guard parts.count >= 3, parts[0] == "mcp" else { return raw }
        let server = parts[1]
        let tool = parts[2...].joined(separator: "_")
        if let input = inputPart {
            return "\(server): \(tool): \(input)"
        }
        return "\(server): \(tool)"
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
            guard let tool = lastToolUse else { return "" }
            return tool.hasPrefix("mcp__") ? Agent.formatMcpToolName(tool) : tool
        case .permission:
            guard let tool = lastToolUse else { return "" }
            let display = tool.hasPrefix("mcp__") ? Agent.formatMcpToolName(tool) : tool
            return "Wants to run: \(display)"
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

    /// Whether the agent was interrupted by the user.
    var isInterrupted: Bool { toolFailure == "interrupt" }

    /// Whether the agent hit a tool error (non-interrupt failure).
    var isToolFailure: Bool { toolFailure == "error" }

    /// Whether the agent's last message indicates an API error/outage.
    var isAPIError: Bool {
        guard let msg = lastMessage?.prefix(60).lowercased() else { return false }
        return msg.contains("api error") || msg.contains("api_error")
            || msg.contains("internal server error") || msg.contains("overloaded")
    }

    /// Whether this is a plan approval permission (ExitPlanMode) vs a dangerous tool permission.
    var isPlanApproval: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("ExitPlanMode")
    }

    /// Whether this is an AskUserQuestion permission (question bubble).
    var isAskingQuestion: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("AskUserQuestion")
    }

    /// Whether the permission is for a Bash command.
    var isBashPermission: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("Bash")
    }

    /// Whether the permission is for a file modification tool (Edit, Write, NotebookEdit).
    var isFilePermission: Bool {
        guard let tool = lastToolUse else { return false }
        let prefixes = ["Edit", "Write", "NotebookEdit"]
        return prefixes.contains { tool.hasPrefix($0) }
    }

    /// Whether the permission is for a web tool (WebSearch, WebFetch).
    var isWebPermission: Bool {
        guard let tool = lastToolUse else { return false }
        let prefixes = ["WebSearch", "WebFetch"]
        return prefixes.contains { tool.hasPrefix($0) }
    }

    /// Whether the permission is for an MCP tool.
    var isMcpPermission: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("mcp__")
    }

    /// Whether the permission is for a GitHub-related tool.
    var isGithubPermission: Bool {
        guard let tool = lastToolUse else { return false }
        if tool.hasPrefix("mcp__github__") { return true }
        guard tool.hasPrefix("Bash") else { return false }
        let lower = tool.lowercased()
        let gitPatterns = ["\"git ", "\"gh ", "\"git\t", "\"gh\t"]
        return gitPatterns.contains { lower.contains($0) }
    }
}

extension Agent {
    static func fixture(
        provider: AgentProvider = .claudeCode,
        sessionId: String = "test-session",
        pid: Int = 99999,
        cwd: String? = "/tmp/test",
        agentType: String? = nil,
        sessionTitle: String? = nil,
        status: AgentStatus = .working,
        lastMessage: String? = nil,
        lastToolUse: String? = nil,
        tty: String? = nil,
        cmuxWorkspace: String? = nil,
        cmuxSurface: String? = nil,
        cmuxSocketPath: String? = nil,
        parentSessionId: String? = nil,
        waitReason: String? = nil,
        toolFailure: String? = nil,
        taskCompletedAt: Int64? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64 = 1000,
        statusChangedAt: Int64? = nil
    ) -> Agent {
        Agent(
            provider: provider,
            sessionId: sessionId, pid: pid, cwd: cwd,
            agentType: agentType, sessionTitle: sessionTitle, status: status,
            lastMessage: lastMessage, lastToolUse: lastToolUse,
            tty: tty,
            cmuxWorkspace: cmuxWorkspace, cmuxSurface: cmuxSurface,
            cmuxSocketPath: cmuxSocketPath, parentSessionId: parentSessionId,
            waitReason: waitReason, toolFailure: toolFailure,
            taskCompletedAt: taskCompletedAt,
            createdAt: createdAt, updatedAt: updatedAt,
            statusChangedAt: statusChangedAt
        )
    }
}
