import Foundation

/// Validates incoming commands and auth tokens.
enum RemoteRouter {

    static func validateAuth(header: String?, validTokens: [String]) -> Bool {
        guard let header, header.hasPrefix("Bearer ") else { return false }
        let token = String(header.dropFirst("Bearer ".count))
        return validTokens.contains(token)
    }

    static func validateCommand(_ command: CommandType, agent: Agent) -> String? {
        guard agent.cmuxSurface != nil else {
            return "Agent is not a cmux session — remote commands not supported"
        }

        switch command {
        case .approve, .deny, .selectOption:
            guard agent.status == .permission else {
                return "Agent is not in permission state"
            }
        case .respond:
            guard agent.status != .working && agent.status != .compacting else {
                return "Agent is currently working"
            }
        case .interrupt:
            break
        }

        return nil
    }
}
