enum ScreenPlacement: String, CaseIterable {
    case allDisplays
    case primaryOnly
    case allExceptPrimary

    var menuTitle: String {
        switch self {
        case .allDisplays:       return "All Displays"
        case .primaryOnly:       return "Primary Only"
        case .allExceptPrimary:  return "All Except Primary"
        }
    }
}
