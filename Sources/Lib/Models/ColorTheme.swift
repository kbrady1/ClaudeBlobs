import SwiftUI

enum ColorTheme: String, CaseIterable {
    case trafficLight
    case oceanDepths
    case sunsetBoulevard
    case neonNights
    case forestFloor
    case candyApple
    case firecracker

    var displayName: String {
        switch self {
        case .trafficLight:    return "Traffic Light"
        case .oceanDepths:     return "Ocean Depths"
        case .sunsetBoulevard: return "Sunset Boulevard"
        case .neonNights:      return "Neon Nights"
        case .forestFloor:     return "Forest Floor"
        case .candyApple:      return "Candy Apple"
        case .firecracker:     return "Firecracker"
        }
    }

    func color(for status: AgentStatus) -> Color {
        switch self {
        case .trafficLight:
            switch status {
            case .starting:   return Color(red: 0.204, green: 0.780, blue: 0.349)
            case .working:    return Color(red: 0.298, green: 0.553, blue: 1.0)
            case .waiting:    return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .permission: return Color(red: 1.0, green: 0.231, blue: 0.188)
            case .compacting:  return Color(red: 0.6, green: 0.4, blue: 1.0)
            case .delegating:  return Color(red: 0.204, green: 0.780, blue: 0.349)
            }
        case .oceanDepths:
            switch status {
            case .starting:   return Color(red: 0.176, green: 0.831, blue: 0.749)
            case .working:    return Color(red: 0.118, green: 0.227, blue: 0.373)
            case .waiting:    return Color(red: 0.431, green: 0.906, blue: 0.718)
            case .permission: return Color(red: 0.973, green: 0.443, blue: 0.443)
            case .compacting:  return Color(red: 0.545, green: 0.361, blue: 0.965)
            case .delegating:  return Color(red: 0.176, green: 0.831, blue: 0.749)
            }
        case .sunsetBoulevard:
            switch status {
            case .starting:   return Color(red: 0.984, green: 0.749, blue: 0.141)
            case .working:    return Color(red: 0.925, green: 0.286, blue: 0.600)
            case .waiting:    return Color(red: 0.992, green: 0.729, blue: 0.455)
            case .permission: return Color(red: 0.863, green: 0.149, blue: 0.149)
            case .compacting:  return Color(red: 0.769, green: 0.710, blue: 0.992)
            case .delegating:  return Color(red: 0.984, green: 0.749, blue: 0.141)
            }
        case .neonNights:
            switch status {
            case .starting:   return Color(red: 0.518, green: 0.800, blue: 0.086)
            case .working:    return Color(red: 0.231, green: 0.510, blue: 0.965)
            case .waiting:    return Color(red: 0.957, green: 0.447, blue: 0.714)
            case .permission: return Color(red: 0.937, green: 0.267, blue: 0.267)
            case .compacting:  return Color(red: 0.133, green: 0.827, blue: 0.933)
            case .delegating:  return Color(red: 0.518, green: 0.800, blue: 0.086)
            }
        case .forestFloor:
            switch status {
            case .starting:   return Color(red: 0.525, green: 0.937, blue: 0.675)
            case .working:    return Color(red: 0.302, green: 0.486, blue: 0.059)
            case .waiting:    return Color(red: 0.961, green: 0.620, blue: 0.043)
            case .permission: return Color(red: 0.706, green: 0.325, blue: 0.035)
            case .compacting:  return Color(red: 0.659, green: 0.333, blue: 0.969)
            case .delegating:  return Color(red: 0.525, green: 0.937, blue: 0.675)
            }
        case .candyApple:
            switch status {
            case .starting:   return Color(red: 0.204, green: 0.827, blue: 0.600)
            case .working:    return Color(red: 0.220, green: 0.741, blue: 0.973)
            case .waiting:    return Color(red: 0.984, green: 0.573, blue: 0.235)
            case .permission: return Color(red: 0.882, green: 0.114, blue: 0.282)
            case .compacting:  return Color(red: 0.655, green: 0.545, blue: 0.980)
            case .delegating:  return Color(red: 0.204, green: 0.827, blue: 0.600)
            }
        case .firecracker:
            switch status {
            case .starting:   return Color(red: 0.639, green: 0.902, blue: 0.208)
            case .working:    return Color(red: 0.145, green: 0.388, blue: 0.922)
            case .waiting:    return Color(red: 0.976, green: 0.451, blue: 0.086)
            case .permission: return Color(red: 0.725, green: 0.110, blue: 0.110)
            case .compacting:  return Color(red: 0.851, green: 0.275, blue: 0.937)
            case .delegating:  return Color(red: 0.639, green: 0.902, blue: 0.208)
            }
        }
    }
}
