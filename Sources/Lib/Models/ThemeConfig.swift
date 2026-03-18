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

    @Published var backgroundMaterial: Bool {
        didSet { UserDefaults.standard.set(backgroundMaterial, forKey: "backgroundMaterial") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "colorTheme") ?? ""
        self.selectedTheme = ColorTheme(rawValue: raw) ?? .trafficLight
        self.backgroundEnabled = UserDefaults.standard.bool(forKey: "collapsedBackgroundEnabled")
        self.backgroundMaterial = UserDefaults.standard.bool(forKey: "backgroundMaterial")
        if let data = UserDefaults.standard.data(forKey: "collapsedBackgroundColor"),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            self.backgroundColor = Color(nsColor)
        } else {
            self.backgroundColor = .black
        }
    }
}
