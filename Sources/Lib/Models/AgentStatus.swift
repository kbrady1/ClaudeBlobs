import SwiftUI

enum AgentStatus: String, Codable, CaseIterable {
    case starting
    case working
    case waiting
    case permission

    var color: Color {
        switch self {
        case .starting:   return Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759
        case .working:    return Color(red: 0.298, green: 0.553, blue: 1.0)    // #4C8DFF
        case .waiting:    return Color(red: 1.0, green: 0.584, blue: 0.0)      // #FF9500
        case .permission: return Color(red: 1.0, green: 0.231, blue: 0.188)    // #FF3B30
        }
    }

    var visibleWhenCollapsed: Bool {
        switch self {
        case .waiting, .permission, .starting: return true
        case .working: return false
        }
    }

    var displayName: String {
        switch self {
        case .starting:   return "Starting"
        case .working:    return "Working"
        case .waiting:    return "Waiting"
        case .permission: return "Needs Permission"
        }
    }
}
