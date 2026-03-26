import Foundation
import Combine

final class SoundConfig: ObservableObject {
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "soundEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "soundEnabled") }
    }
    @Published var greenSound: String = UserDefaults.standard.string(forKey: "soundGreen") ?? "Pop" {
        didSet { UserDefaults.standard.set(greenSound, forKey: "soundGreen") }
    }
    @Published var orangeSound: String = UserDefaults.standard.string(forKey: "soundOrange") ?? "Glass" {
        didSet { UserDefaults.standard.set(orangeSound, forKey: "soundOrange") }
    }
    @Published var redSound: String = UserDefaults.standard.string(forKey: "soundRed") ?? "Ping" {
        didSet { UserDefaults.standard.set(redSound, forKey: "soundRed") }
    }
    @Published var doneSound: String = UserDefaults.standard.string(forKey: "soundDone") ?? "" {
        didSet { UserDefaults.standard.set(doneSound, forKey: "soundDone") }
    }

    /// Available system sound names, discovered from /System/Library/Sounds.
    static let availableSounds: [String] = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "aiff" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()
}
