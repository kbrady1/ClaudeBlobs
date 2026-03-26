import AppKit

final class SoundPlayer {
    private let config: SoundConfig

    init(config: SoundConfig) {
        self.config = config
    }

    /// Play sounds for a batch of status changes. Deduplicates so each color sounds at most once.
    func playForChanges(_ statuses: [AgentStatus]) {
        guard config.isEnabled else { return }

        var playedColors: Set<String> = []
        for status in statuses {
            guard let color = colorGroup(for: status),
                  !playedColors.contains(color) else { continue }
            playedColors.insert(color)
            play(soundName(for: color))
        }
    }

    /// Preview a specific sound by name.
    func preview(_ name: String) {
        play(name)
    }

    private func colorGroup(for status: AgentStatus) -> String? {
        switch status {
        case .starting:   return "green"
        case .waiting:    return "orange"
        case .permission: return "red"
        case .working, .compacting: return nil
        }
    }

    private func soundName(for color: String) -> String {
        switch color {
        case "green":  return config.greenSound
        case "orange": return config.orangeSound
        case "red":    return config.redSound
        default:       return ""
        }
    }

    private func play(_ name: String) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}
