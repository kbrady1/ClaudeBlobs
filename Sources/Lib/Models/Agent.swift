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
    case stale   // X-eyes
    case hung    // X-eyes + desaturated

    /// Idle threshold in seconds (gray/desaturated). Configurable via UserDefaults.
    static var idleThreshold: Int64 {
        let val = UserDefaults.standard.integer(forKey: "idleThresholdSeconds")
        return val > 0 ? Int64(val) : 3600  // default 1 hr
    }

    /// X-eyes threshold: half the idle threshold, minimum 300s (5 min).
    static var staleThreshold: Int64 {
        max(300, idleThreshold / 2)
    }

    init(updatedAt: Int64) {
        let ageSeconds = (Int64(Date().timeIntervalSince1970 * 1000) - updatedAt) / 1000
        if ageSeconds > Self.idleThreshold { self = .hung }
        else if ageSeconds > Self.staleThreshold { self = .stale }
        else { self = .active }
    }
}

struct Agent: Codable, Identifiable, Equatable, Sendable {
    var provider: AgentProvider
    let sessionId: String
    let pid: Int
    var cwd: String?
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
    var rawLastMessage: String?
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
        case rawLastMessage
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
        rawLastMessage = try container.decodeIfPresent(String.self, forKey: .rawLastMessage)
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
        guard tool.hasPrefix("Bash: ") || tool.hasPrefix("Bash:") else { return false }
        let cmd = tool.dropFirst(tool.hasPrefix("Bash: ") ? 6 : 5).lowercased()
        return cmd.hasPrefix("git ") || cmd.hasPrefix("gh ") || cmd == "git" || cmd == "gh"
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
            return cleanMessage
        case .working:
            return cleanToolUse
        case .permission:
            return permissionToolUse
        case .starting:
            return "Starting up..."
        case .compacting:
            return "Compacting context..."
        }
    }

    // MARK: - Clean display text

    /// Cleaned message for speech bubble display. Strips markdown and filler preambles.
    /// Falls back to rawLastMessage if lastMessage is too short/vague.
    var cleanMessage: String {
        let msg = lastMessage ?? ""
        if msg.isEmpty { return "" }

        var text = Agent.stripMarkdown(msg)
        text = Agent.stripFillerPreamble(text)

        // If cleaned text is too short, try extracting from rawLastMessage
        if text.count < 15, let rawMsg = rawLastMessage {
            let rawCleaned = Agent.cleanRawMessage(rawMsg, maxLength: 120)
            if rawCleaned.count > text.count {
                return rawCleaned
            }
        }

        return String(text.prefix(120))
    }

    /// Longer cleaned message for push notifications. Uses rawLastMessage for more context.
    var notificationMessage: String {
        guard let raw = rawLastMessage, !raw.isEmpty else { return cleanMessage }
        return Agent.cleanRawMessage(raw, maxLength: 300)
    }

    /// Human-readable tool use for working state (gerund form: "Reading", "Editing").
    var cleanToolUse: String {
        guard let tool = lastToolUse else { return "" }
        return Agent.formatToolForDisplay(tool, imperative: false)
    }

    /// Human-readable tool use for permission state (imperative form: "Read", "Edit").
    var permissionToolUse: String {
        guard let tool = lastToolUse else { return "" }
        return Agent.formatToolForDisplay(tool, imperative: true)
    }

    /// Longer permission tool use for the popover preview (no truncation).
    var permissionToolUseExpanded: String {
        guard let tool = lastToolUse else { return "" }
        return Agent.formatToolForDisplay(tool, imperative: true, maxCommandLength: 200)
    }

    // MARK: - Text cleaning helpers

    static func stripMarkdown(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: #"^- "#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func stripFillerPreamble(_ text: String) -> String {
        let pattern = #"^(?:Good|Great|Perfect|Excellent|Sure|Okay|Now I have[^.]*|Here(?:'s| is)[^.]*|Let me[^.]*)[.,!]?\s*"#
        let result = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Cleans a raw multi-line message into a single-line summary.
    static func cleanRawMessage(_ raw: String, maxLength: Int) -> String {
        var text = raw
        // Strip markdown
        text = text.replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
        // Collapse paragraph breaks to dashes, newlines to spaces
        text = text.replacingOccurrences(of: #"\n\n+"#, with: " \u{2014} ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n"#, with: " ", options: .regularExpression)
        // Strip filler preambles
        text = stripFillerPreamble(text)
        // Collapse multiple spaces
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespaces)
        return String(text.prefix(maxLength))
    }

    /// Formats a tool use string for human-readable display.
    /// - Parameter imperative: true for permission state ("Read X"), false for working state ("Reading X")
    static func formatToolForDisplay(_ tool: String, imperative: Bool, maxCommandLength: Int = 60) -> String {
        // Internal tools that show JSON — always use friendly names
        if tool.hasPrefix("TaskUpdate:") || tool.hasPrefix("TaskCreate:") { return "Updating tasks" }
        if tool.hasPrefix("TaskGet:") || tool.hasPrefix("TaskGet") { return "Checking tasks" }
        if tool.hasPrefix("TaskList") { return "Checking tasks" }
        if tool.hasPrefix("ExitPlanMode") { return imperative ? "Approve plan" : "Submitting plan" }
        if tool.hasPrefix("EnterPlanMode") { return "Planning" }
        if tool.hasPrefix("ToolSearch") { return "Looking up tools" }
        if tool.hasPrefix("Skill:") || tool.hasPrefix("Skill ") { return "Loading skill" }

        // AskUserQuestion — extract the question text
        if tool.hasPrefix("AskUserQuestion:") {
            let json = String(tool.dropFirst("AskUserQuestion:".count)).trimmingCharacters(in: .whitespaces)
            if let questionText = extractAskQuestion(from: json) {
                return imperative ? "Ask: \(questionText)" : "Ask: \(questionText)"
            }
            return imperative ? "Ask: ..." : "Asking question"
        }

        // Bash — strip paths, redirects, pipes
        if tool.hasPrefix("Bash: ") {
            let cmd = cleanBashCommand(String(tool.dropFirst(6)), maxLength: maxCommandLength)
            return imperative ? "Run: \(cmd)" : cmd
        }
        if tool == "Bash" { return "Bash" }

        // File tools
        if tool.hasPrefix("Read: ") {
            let file = String(tool.dropFirst(6))
            return imperative ? "Read \(file)" : "Reading \(file)"
        }
        if tool.hasPrefix("Edit: ") {
            let file = String(tool.dropFirst(6))
            return imperative ? "Edit \(file)" : "Editing \(file)"
        }
        if tool.hasPrefix("Write: ") {
            let file = String(tool.dropFirst(7))
            return imperative ? "Write \(file)" : "Writing \(file)"
        }
        if tool.hasPrefix("NotebookEdit: ") {
            let file = String(tool.dropFirst(14))
            return imperative ? "Edit \(file)" : "Editing \(file)"
        }

        // Search tools
        if tool.hasPrefix("Grep: ") {
            let pattern = String(tool.dropFirst(6)).components(separatedBy: "|").first ?? tool
            return "Search: \(pattern.trimmingCharacters(in: .whitespaces))"
        }
        if tool.hasPrefix("Glob: ") {
            let pattern = String(tool.dropFirst(6))
            return "Search: \(pattern)"
        }

        // Web tools
        if tool.hasPrefix("WebSearch: ") { return "Web: \(tool.dropFirst(11))" }
        if tool.hasPrefix("WebFetch: ") { return "Web: \(tool.dropFirst(10))" }

        // MCP tools
        if tool.hasPrefix("mcp__") { return Agent.formatMcpToolName(tool) }

        // Agent subagents
        if tool.hasPrefix("Agent: ") { return String(tool.prefix(60)) }

        return tool
    }

    /// Cleans a bash command for display: strips paths, cd prefixes, redirects, pipes.
    static func cleanBashCommand(_ cmd: String, maxLength: Int = 60) -> String {
        var c = cmd
        // Strip cd prefix to a directory
        c = c.replacingOccurrences(of: #"^cd\s+\S+\s*&&\s*"#, with: "", options: .regularExpression)
        // Strip absolute home paths: /Users/foo/SourceCode/bar/ → ""
        c = c.replacingOccurrences(of: #"/Users/\w+/SourceCode/[^/]+/"#, with: "", options: .regularExpression)
        // Strip remaining home paths: /Users/foo/ → ~/
        c = c.replacingOccurrences(of: #"/Users/\w+/"#, with: "~/", options: .regularExpression)
        // Strip output redirects (2>&1 and everything after)
        c = c.replacingOccurrences(of: #"\s*2>&1.*$"#, with: "", options: .regularExpression)
        // Strip trailing pipes to tail/head/grep
        c = c.replacingOccurrences(of: #"\s*\|\s*(?:tail|head|grep)\b.*$"#, with: "", options: .regularExpression)
        c = c.trimmingCharacters(in: .whitespaces)
        return String(c.prefix(maxLength))
    }

    /// Extracts the first question text from AskUserQuestion JSON.
    static func extractAskQuestion(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = obj["questions"] as? [[String: Any]],
              let first = questions.first,
              let question = first["question"] as? String else {
            return nil
        }
        return String(question.prefix(80))
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
        guard tool.hasPrefix("Bash: ") || tool.hasPrefix("Bash:") else { return false }
        let cmd = tool.dropFirst(tool.hasPrefix("Bash: ") ? 6 : 5).lowercased()
        return cmd.hasPrefix("git ") || cmd.hasPrefix("gh ") || cmd == "git" || cmd == "gh"
    }
}

extension Agent {
    /// Returns the most urgent status among this agent and its children.
    /// Uses `AgentStatus.sortPriority` (lower = more urgent).
    static func effectiveStatus(of agent: Agent, children: [Agent]) -> AgentStatus {
        guard !children.isEmpty else { return agent.status }
        var best = agent.status
        for child in children {
            if child.status.sortPriority < best.sortPriority {
                best = child.status
            }
        }
        return best
    }

    /// Returns the child with the most urgent status, if any.
    static func mostUrgentChild(of agent: Agent, children: [Agent]) -> Agent? {
        guard !children.isEmpty else { return nil }
        return children.min(by: { $0.status.sortPriority < $1.status.sortPriority })
    }

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
        rawLastMessage: String? = nil,
        toolFailure: String? = nil,
        taskCompletedAt: Int64? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64 = 1000,
        statusChangedAt: Int64? = nil
    ) -> Agent {
        var agent = Agent(
            provider: provider,
            sessionId: sessionId, pid: pid, cwd: cwd,
            agentType: agentType, sessionTitle: sessionTitle, status: status,
            lastMessage: lastMessage, lastToolUse: lastToolUse,
            tty: tty,
            cmuxWorkspace: cmuxWorkspace, cmuxSurface: cmuxSurface,
            cmuxSocketPath: cmuxSocketPath, parentSessionId: parentSessionId,
            waitReason: waitReason,
            toolFailure: toolFailure,
            taskCompletedAt: taskCompletedAt,
            createdAt: createdAt, updatedAt: updatedAt,
            statusChangedAt: statusChangedAt
        )
        agent.rawLastMessage = rawLastMessage
        return agent
    }
}
