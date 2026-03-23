import Foundation

/// Messages sent from server to client over WebSocket
enum RemoteMessage: Codable {
    case snapshot(agents: [Agent])
    case agentUpdated(agent: Agent)
    case agentRemoved(sessionId: String)
    case heartbeat

    private enum CodingKeys: String, CodingKey {
        case type, agents, agent, sessionId
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "snapshot":
            let agents = try container.decode([Agent].self, forKey: .agents)
            self = .snapshot(agents: agents)
        case "agentUpdated":
            let agent = try container.decode(Agent.self, forKey: .agent)
            self = .agentUpdated(agent: agent)
        case "agentRemoved":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .agentRemoved(sessionId: sessionId)
        case "heartbeat":
            self = .heartbeat
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }
}

/// Command types the phone can send
enum CommandType: String, Codable {
    case approve, deny, respond, interrupt
}

/// Incoming command from phone
struct CommandRequest: Codable {
    let command: CommandType
    let sessionId: String
    let text: String?
}

/// Response to a command
struct CommandResponse: Codable {
    let success: Bool
    let error: String?

    init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
    }
}
