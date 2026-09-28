import Foundation

extension Agent {
    /// How long a worker may go without writing its status file before the
    /// board surfaces it as stalled. Configurable via UserDefaults.
    static var orchestrateSilenceThreshold: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "orchestrateSilenceMinutes")
        return TimeInterval(minutes > 0 ? minutes : 60) * 60
    }

    /// Seconds since this session last wrote its status file.
    func silenceSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince1970 - TimeInterval(updatedAt) / 1000
    }

    /// Whether an orchestrated worker needs the developer despite its
    /// orchestrator. The orchestrator drives the worker whatever the worker
    /// says, so only silence past the threshold hands it back.
    func orchestrateNeedsHuman(now: Date = Date(), silenceThreshold: TimeInterval = Agent.orchestrateSilenceThreshold) -> Bool {
        silenceSeconds(now: now) > silenceThreshold
    }
}
