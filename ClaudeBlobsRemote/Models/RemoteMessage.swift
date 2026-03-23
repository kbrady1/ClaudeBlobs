// ClaudeBlobsRemote/Models/RemoteMessage.swift
// Mirrors the macOS RemoteTypes — decode-only for incoming messages

import Foundation

/// Agent paired with its host app icon for network transmission.
struct AgentSnapshot: Codable {
    let agent: Agent
    let appIconPNG: Data?  // PNG-encoded host app icon, if available
}

enum RemoteMessage: Codable {
    case snapshot(agents: [AgentSnapshot])
    case agentUpdated(agent: AgentSnapshot)
    case agentRemoved(sessionId: String)
    case heartbeat

    private enum CodingKeys: String, CodingKey {
        case type, agents, agent, sessionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "snapshot":
            self = .snapshot(agents: try container.decode([AgentSnapshot].self, forKey: .agents))
        case "agentUpdated":
            self = .agentUpdated(agent: try container.decode(AgentSnapshot.self, forKey: .agent))
        case "agentRemoved":
            self = .agentRemoved(sessionId: try container.decode(String.self, forKey: .sessionId))
        case "heartbeat":
            self = .heartbeat
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshot(let agents):
            try container.encode("snapshot", forKey: .type)
            try container.encode(agents, forKey: .agents)
        case .agentUpdated(let agent):
            try container.encode("agentUpdated", forKey: .type)
            try container.encode(agent, forKey: .agent)
        case .agentRemoved(let sessionId):
            try container.encode("agentRemoved", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .heartbeat:
            try container.encode("heartbeat", forKey: .type)
        }
    }
}

enum CommandType: String, Codable {
    case approve, deny, respond, interrupt
}

struct CommandRequest: Codable {
    let command: CommandType
    let sessionId: String
    let text: String?
}
