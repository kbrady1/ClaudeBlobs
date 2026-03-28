import SwiftUI

enum AgentStatus: String, Codable, CaseIterable {
    case starting
    case working
    case waiting
    case permission
    case compacting
    case delegating

    var color: Color {
        color(for: .trafficLight)
    }

    func color(for theme: ColorTheme) -> Color {
        theme.color(for: self)
    }

    var visibleWhenCollapsed: Bool {
        switch self {
        case .waiting, .permission, .starting, .delegating: return true
        case .working, .compacting: return false
        }
    }

    /// Priority for display ordering: lower = more urgent (leftmost).
    /// Order: red (permission), orange (waiting), delegating, green (starting), blue (working), purple (compacting).
    var sortPriority: Int {
        switch self {
        case .permission:  return 0
        case .waiting:     return 1
        case .delegating:  return 2
        case .starting:    return 3
        case .working:     return 4
        case .compacting:  return 5
        }
    }

    var displayName: String {
        switch self {
        case .starting:    return "Starting"
        case .working:     return "Working"
        case .waiting:     return "Waiting"
        case .permission:  return "Needs Permission"
        case .compacting:  return "Compacting"
        case .delegating:  return "Delegating"
        }
    }
}
