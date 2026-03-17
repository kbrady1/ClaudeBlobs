import SwiftUI

enum AgentStatus: String, Codable, CaseIterable {
    case starting
    case working
    case waiting
    case permission
    case compacting

    var color: Color {
        color(for: .trafficLight)
    }

    func color(for theme: ColorTheme) -> Color {
        theme.color(for: self)
    }

    var visibleWhenCollapsed: Bool {
        switch self {
        case .waiting, .permission, .starting: return true
        case .working, .compacting: return false
        }
    }

    var displayName: String {
        switch self {
        case .starting:   return "Starting"
        case .working:    return "Working"
        case .waiting:    return "Waiting"
        case .permission: return "Needs Permission"
        case .compacting: return "Compacting"
        }
    }
}
