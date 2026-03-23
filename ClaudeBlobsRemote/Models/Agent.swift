// ClaudeBlobsRemote/Models/Agent.swift
// Minimal Agent model for iOS — mirrors the macOS Agent's Codable format

import Foundation

enum AgentStatus: String, Codable, CaseIterable {
    case starting, working, waiting, permission, compacting

    var displayName: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .permission: return "Permission"
        case .compacting: return "Compacting"
        }
    }

    var sortPriority: Int {
        switch self {
        case .permission: return 0
        case .waiting: return 1
        case .starting: return 2
        case .working: return 3
        case .compacting: return 4
        }
    }
}

struct Agent: Codable, Identifiable {
    let sessionId: String
    let pid: Int
    let cwd: String?
    let status: AgentStatus
    let lastMessage: String?
    let rawLastMessage: String?
    let lastToolUse: String?
    let cmuxWorkspace: String?
    let cmuxSurface: String?
    let cmuxSocketPath: String?
    let parentSessionId: String?
    let waitReason: String?
    let toolFailure: String?
    let tty: String?
    let agentType: String?
    let taskCompletedAt: Int64?
    let createdAt: Int64?
    let updatedAt: Int64
    let statusChangedAt: Int64?

    var id: String { sessionId }
    var isCmuxSession: Bool { cmuxSurface != nil }
    var projectName: String {
        cwd?.split(separator: "/").last.map(String.init) ?? "Unknown"
    }

    // MARK: - Sprite View Computed Properties

    var isDone: Bool { waitReason == "done" }

    var isCoding: Bool {
        guard let tool = lastToolUse else { return false }
        let codingPrefixes = ["Edit", "Write", "Bash", "NotebookEdit"]
        return codingPrefixes.contains { tool.hasPrefix($0) }
    }

    var isSearching: Bool {
        guard let tool = lastToolUse else { return false }
        let webPrefixes = ["WebSearch", "WebFetch"]
        return webPrefixes.contains { tool.hasPrefix($0) }
    }

    var isExploring: Bool {
        guard let tool = lastToolUse else { return false }
        let explorePrefixes = ["Read", "Grep", "Glob", "LSP", "Agent"]
        return explorePrefixes.contains { tool.hasPrefix($0) }
    }

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

    var isMcpTool: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("mcp__")
    }

    var isGithubTool: Bool {
        guard let tool = lastToolUse else { return false }
        if tool.hasPrefix("mcp__github__") { return true }
        guard tool.hasPrefix("Bash: ") || tool.hasPrefix("Bash:") else { return false }
        let cmd = tool.dropFirst(tool.hasPrefix("Bash: ") ? 6 : 5).lowercased()
        return cmd.hasPrefix("git ") || cmd.hasPrefix("gh ") || cmd == "git" || cmd == "gh"
    }

    var isTaskJustCompleted: Bool {
        guard let ts = taskCompletedAt else { return false }
        let ageMs = Int64(Date().timeIntervalSince1970 * 1000) - ts
        return ageMs >= 0 && ageMs < 3000
    }

    var isInterrupted: Bool { toolFailure == "interrupt" }
    var isToolFailure: Bool { toolFailure == "error" }

    var isAPIError: Bool {
        guard let msg = lastMessage?.prefix(60).lowercased() else { return false }
        return msg.contains("api error") || msg.contains("api_error")
            || msg.contains("internal server error") || msg.contains("overloaded")
    }

    var isPlanApproval: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("ExitPlanMode")
    }

    var isAskingQuestion: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("AskUserQuestion")
    }

    var isBashPermission: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("Bash")
    }

    var isFilePermission: Bool {
        guard let tool = lastToolUse else { return false }
        let prefixes = ["Edit", "Write", "NotebookEdit"]
        return prefixes.contains { tool.hasPrefix($0) }
    }

    var isWebPermission: Bool {
        guard let tool = lastToolUse else { return false }
        let prefixes = ["WebSearch", "WebFetch"]
        return prefixes.contains { tool.hasPrefix($0) }
    }

    var isMcpPermission: Bool {
        guard let tool = lastToolUse else { return false }
        return tool.hasPrefix("mcp__")
    }

    var isGithubPermission: Bool {
        guard let tool = lastToolUse else { return false }
        if tool.hasPrefix("mcp__github__") { return true }
        guard tool.hasPrefix("Bash: ") || tool.hasPrefix("Bash:") else { return false }
        let cmd = tool.dropFirst(tool.hasPrefix("Bash: ") ? 6 : 5).lowercased()
        return cmd.hasPrefix("git ") || cmd.hasPrefix("gh ") || cmd == "git" || cmd == "gh"
    }

    // Note: Uses default Codable synthesis. Any fields absent in JSON
    // decode as nil (optionals) or use default values. If the macOS model
    // adds new fields, they are silently ignored here.
}

// MARK: - Agent Staleness (simplified from macOS — no UserDefaults on iOS)

enum AgentStaleness: Sendable, Equatable {
    case active
    case stale   // X-eyes
    case hung    // X-eyes + desaturated

    static let staleThresholdSeconds: Int64 = 300   // 5 min
    static let hungThresholdSeconds: Int64 = 3600    // 1 hr

    init(updatedAt: Int64) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let ageSeconds = (nowMs - updatedAt) / 1000
        if ageSeconds >= Self.hungThresholdSeconds {
            self = .hung
        } else if ageSeconds >= Self.staleThresholdSeconds {
            self = .stale
        } else {
            self = .active
        }
    }
}
