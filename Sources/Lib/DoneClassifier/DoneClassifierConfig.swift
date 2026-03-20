import Foundation
import Combine

final class DoneClassifierConfig: ObservableObject {
    @Published var appleIntelligenceEnabled: Bool = UserDefaults.standard.bool(forKey: "doneClassifierAppleIntelligence") {
        didSet { UserDefaults.standard.set(appleIntelligenceEnabled, forKey: "doneClassifierAppleIntelligence") }
    }

    var isAppleIntelligenceAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}
