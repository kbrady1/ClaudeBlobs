import Foundation

/// A sentinel line an `/orchestrate` worker prints to report to its orchestrator.
///
/// Worker sessions are driven by an orchestrator, not by the developer, so the
/// board hides them until they need a human. The sentinel says which case a
/// worker is in.
enum OrchestrateSentinel: String, Equatable, Sendable, CaseIterable {
    case status = "STATUS"
    case question = "QUESTION"
    case blocked = "BLOCKED"
    case planReady = "PLAN-READY"
    case pr = "PR"
    case done = "DONE"

    /// Longest tokens first, so `PLAN-READY` wins over a `PR` prefix match.
    fileprivate static var tokensByLength: [OrchestrateSentinel] {
        allCases.sorted { $0.rawValue.count > $1.rawValue.count }
    }

    /// The orchestrator answers questions, plans, and status lines itself.
    /// Only these cases still need the developer.
    var needsHuman: Bool {
        switch self {
        case .blocked, .done: return true
        case .status, .question, .planReady, .pr: return false
        }
    }

    var label: String {
        switch self {
        case .status: return "Working"
        case .question: return "Asked the orchestrator"
        case .blocked: return "Blocked"
        case .planReady: return "Plan ready for review"
        case .pr: return "Pull request open"
        case .done: return "Done"
        }
    }
}

/// One parsed sentinel line: the kind plus the text after the token.
struct OrchestrateReport: Equatable, Sendable {
    let sentinel: OrchestrateSentinel
    let detail: String

    /// Parses the last sentinel line in a message. Workers print sentinels on
    /// their own line, so each line is matched from its start.
    static func parse(_ text: String?) -> OrchestrateReport? {
        guard let text, text.contains("ORCHESTRATE-") else { return nil }
        var found: OrchestrateReport?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let report = parseLine(line) else { continue }
            found = report
        }
        return found
    }

    private static func parseLine(_ line: String) -> OrchestrateReport? {
        // Workers sometimes wrap the line in quotes or markdown emphasis.
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'*`_ "))
        guard stripped.hasPrefix("ORCHESTRATE-") else { return nil }
        let rest = stripped.dropFirst("ORCHESTRATE-".count)
        for sentinel in OrchestrateSentinel.tokensByLength where rest.hasPrefix(sentinel.rawValue) {
            let detail = rest.dropFirst(sentinel.rawValue.count)
            // Require a separator so ORCHESTRATE-PRIVATE does not read as PR.
            guard detail.isEmpty || detail.first == " " || detail.first == ":" else { continue }
            return OrchestrateReport(
                sentinel: sentinel,
                detail: detail.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).trimmingCharacters(in: .whitespaces)
            )
        }
        return nil
    }
}

extension Agent {
    /// The most recent sentinel this session printed, if any.
    var orchestrateReport: OrchestrateReport? {
        OrchestrateReport.parse(rawLastMessage) ?? OrchestrateReport.parse(lastMessage)
    }

    /// Whether the status file currently carries the session's own message.
    /// The hooks null it on every tool call, so an absent message is not a
    /// turn — it says nothing about whether an orchestrator is driving.
    var hasCurrentMessage: Bool {
        rawLastMessage != nil || lastMessage != nil
    }

    /// How long a worker may go without writing its status file before the
    /// board surfaces it as stalled. Configurable via UserDefaults.
    static var orchestrateSilenceThreshold: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "orchestrateSilenceMinutes")
        return TimeInterval(minutes > 0 ? minutes : 30) * 60
    }

    /// Seconds since this session last wrote its status file.
    func silenceSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince1970 - TimeInterval(updatedAt) / 1000
    }

    /// Whether an orchestrated worker needs the developer despite its
    /// orchestrator: it reported blocked or done, it hit an error, or it has
    /// gone silent past the threshold.
    func orchestrateNeedsHuman(now: Date = Date(), silenceThreshold: TimeInterval = Agent.orchestrateSilenceThreshold) -> Bool {
        if let report = orchestrateReport, report.sentinel.needsHuman { return true }
        if toolFailure != nil { return true }
        if isAPIError { return true }
        return silenceSeconds(now: now) > silenceThreshold
    }
}
