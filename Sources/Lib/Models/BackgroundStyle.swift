import SwiftUI

enum BackgroundStyle {
    case color(Color)
    case material
    case glass
    case glassClear

    var isGlass: Bool {
        switch self {
        case .glass, .glassClear: return true
        case .color, .material: return false
        }
    }
}

/// User-selectable kind, persisted in UserDefaults.
enum BackgroundKind: String, CaseIterable {
    case color
    case material
    case glass
    case glassClear

    var displayName: String {
        switch self {
        case .color: return "Color"
        case .material: return "Material (blur)"
        case .glass: return "Glass"
        case .glassClear: return "Glass (clear)"
        }
    }
}
