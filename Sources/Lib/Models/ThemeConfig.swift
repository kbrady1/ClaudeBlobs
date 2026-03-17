import Foundation
import Combine

final class ThemeConfig: ObservableObject {
    @Published var selectedTheme: ColorTheme {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: "colorTheme") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "colorTheme") ?? ""
        self.selectedTheme = ColorTheme(rawValue: raw) ?? .trafficLight
    }
}
