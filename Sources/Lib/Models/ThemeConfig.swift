import Foundation
import Combine
import SwiftUI

final class ThemeConfig: ObservableObject {
    @Published var selectedTheme: ColorTheme {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: "colorTheme") }
    }

    @Published var backgroundEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundEnabled, forKey: "collapsedBackgroundEnabled") }
    }

    @Published var backgroundColor: Color {
        didSet {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(backgroundColor), requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "collapsedBackgroundColor")
            }
        }
    }

    @Published var backgroundKind: BackgroundKind {
        didSet { UserDefaults.standard.set(backgroundKind.rawValue, forKey: "backgroundKind") }
    }

    /// When false, the background is only drawn while the HUD is expanded.
    @Published var backgroundShownWhenCollapsed: Bool {
        didSet { UserDefaults.standard.set(backgroundShownWhenCollapsed, forKey: "backgroundShownWhenCollapsed") }
    }

    @Published var prominentStateChangesDisabled: Bool {
        didSet { UserDefaults.standard.set(prominentStateChangesDisabled, forKey: "prominentStateChangesDisabled") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "colorTheme") ?? ""
        self.selectedTheme = ColorTheme(rawValue: raw) ?? .trafficLight
        self.backgroundEnabled = UserDefaults.standard.bool(forKey: "collapsedBackgroundEnabled")
        if let raw = UserDefaults.standard.string(forKey: "backgroundKind"),
           let kind = BackgroundKind(rawValue: raw) {
            self.backgroundKind = kind
        } else if UserDefaults.standard.bool(forKey: "backgroundMaterial") {
            self.backgroundKind = .material
        } else {
            self.backgroundKind = .color
        }
        if UserDefaults.standard.object(forKey: "backgroundShownWhenCollapsed") != nil {
            self.backgroundShownWhenCollapsed = UserDefaults.standard.bool(forKey: "backgroundShownWhenCollapsed")
        } else {
            self.backgroundShownWhenCollapsed = true
        }
        self.prominentStateChangesDisabled = UserDefaults.standard.bool(forKey: "prominentStateChangesDisabled")
        if let data = UserDefaults.standard.data(forKey: "collapsedBackgroundColor"),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            self.backgroundColor = Color(nsColor)
        } else {
            self.backgroundColor = .black
        }
    }
}
