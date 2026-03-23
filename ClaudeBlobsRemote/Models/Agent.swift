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

    // Note: Uses default Codable synthesis. Any fields absent in JSON
    // decode as nil (optionals) or use default values. If the macOS model
    // adds new fields, they are silently ignored here.
}
