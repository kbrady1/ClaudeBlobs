enum AppIconVisibility: String, CaseIterable {
    case expanded
    case always
    case never

    var menuTitle: String {
        switch self {
        case .expanded: return "When Expanded"
        case .always:   return "Always"
        case .never:    return "Never"
        }
    }
}
