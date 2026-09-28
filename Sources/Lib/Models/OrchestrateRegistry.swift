import Foundation

/// One ticket an `/orchestrate` run is driving, joined to the session running it.
///
/// The orchestrate daemon records each unit's Superset terminal id, not its
/// Claude session id, so `terminalId` is what matches `Agent.supersetTerminal`.
struct OrchestrateUnit: Equatable, Sendable {
    /// The Notion ticket id, e.g. `ENG-17773`.
    let ticket: String
    /// The project this unit belongs to, e.g. `PLN-3404`.
    let project: String
    let projectTitle: String
    let title: String
    let stage: OrchestrateStage
    /// The orchestrator has parked this unit; its worker is no longer driven.
    let paused: Bool
    /// The unit's gate policy, e.g. `operator` when a human approves before the
    /// pull request opens. This is the policy for when the gate is eventually
    /// reached, not a signal that the unit is waiting on a human now — read
    /// `paused` for that. Kept for display only.
    let gate: String?
    let prUrl: String?
    /// The Superset terminal the unit's worker runs in.
    let terminalId: String

    /// Whether an orchestrator is currently answering for this worker, so the
    /// board can park it out of the developer's way.
    ///
    /// A paused unit is one the orchestrator has stopped prodding, so it comes
    /// back to the developer. So does a unit that has reached a terminal stage.
    var isDriven: Bool {
        !paused && stage.isDriven
    }

    /// Short board label, e.g. `ENG-17773 · implementing`.
    var label: String { "\(ticket) · \(stage.label)" }
}

/// Where a unit sits in the orchestrate pipeline.
///
/// The daemon has used two names for the stage that parks a unit after its
/// implementation is written: `implement-done` originally, `verify` after the
/// verification gate moved ahead of the pull request. Both appear in state
/// files on disk, so both decode to `verify`.
enum OrchestrateStage: Equatable, Sendable {
    case queued
    case plan
    case planReview
    case planApproved
    case implement
    case verify
    case review
    case done
    case abandoned
    /// A stage this version of ClaudeBlobs does not know. Treated as driven,
    /// so a newer daemon's vocabulary never leaks workers into the HUD.
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "queued": self = .queued
        case "plan": self = .plan
        case "plan-review": self = .planReview
        case "plan-approved": self = .planApproved
        case "implement": self = .implement
        case "verify", "implement-done": self = .verify
        case "review": self = .review
        case "done": self = .done
        case "abandoned": self = .abandoned
        default: self = .unknown(raw)
        }
    }

    /// Whether the orchestrator is still driving a unit at this stage. A unit
    /// that has finished or been dropped belongs to the developer again.
    var isDriven: Bool {
        switch self {
        case .done, .abandoned: return false
        default: return true
        }
    }

    var label: String {
        switch self {
        case .queued: return "queued"
        case .plan: return "planning"
        case .planReview: return "plan in review"
        case .planApproved: return "plan approved"
        case .implement: return "implementing"
        case .verify: return "verifying"
        case .review: return "in review"
        case .done: return "done"
        case .abandoned: return "abandoned"
        case .unknown(let raw): return raw
        }
    }
}

/// A snapshot of every `/orchestrate` run on this machine, read from the
/// cross-run registry and the state file each run points at.
///
/// The registry lives at `~/.superset/orchestrate/registry.json` and is
/// rewritten by every daemon every few seconds. Each daemon prunes entries
/// whose process is gone, so a crashed run self-heals — but only once some
/// daemon writes again. ClaudeBlobs re-checks liveness itself so a machine
/// with no running daemon does not keep hiding workers forever.
struct OrchestrateSnapshot: Equatable, Sendable {
    /// Every driven unit, keyed by the Superset terminal its worker runs in.
    let unitsByTerminal: [String: OrchestrateUnit]

    static let empty = OrchestrateSnapshot(unitsByTerminal: [:])

    func unit(forTerminal terminalId: String?) -> OrchestrateUnit? {
        guard let terminalId else { return nil }
        return unitsByTerminal[terminalId]
    }

    static var defaultRegistryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".superset/orchestrate/registry.json")
    }
}

/// Decodes the registry and the state files it references.
enum OrchestrateRegistry {
    /// Reads every live run's units.
    ///
    /// `isProcessAlive` is injected so tests can describe a dead daemon without
    /// needing a real process.
    static func load(
        registryURL: URL = OrchestrateSnapshot.defaultRegistryURL,
        isProcessAlive: (Int) -> Bool = { kill(Int32($0), 0) == 0 || errno == EPERM }
    ) -> OrchestrateSnapshot {
        guard let data = try? Data(contentsOf: registryURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let orchestrators = root["orchestrators"] as? [String: Any] else {
            return .empty
        }

        var units: [String: OrchestrateUnit] = [:]
        for (_, value) in orchestrators {
            guard let entry = value as? [String: Any] else { continue }
            // A daemon that died without unregistering leaves its entry behind.
            // Its workers are nobody's responsibility now, so they come back to
            // the developer rather than staying hidden.
            if let pid = entry["pid"] as? Int, !isProcessAlive(pid) { continue }
            guard let statePath = entry["statePath"] as? String else { continue }

            // unitSessionIds maps ticket -> Superset terminal id. The state file
            // carries the same terminal ids, but the registry is refreshed more
            // often, so it is the authority on which terminal a unit owns now.
            let terminalsByTicket = (entry["unitSessionIds"] as? [String: String]) ?? [:]
            guard !terminalsByTicket.isEmpty else { continue }

            for unit in loadState(at: URL(fileURLWithPath: statePath), terminalsByTicket: terminalsByTicket) {
                units[unit.terminalId] = unit
            }
        }
        return OrchestrateSnapshot(unitsByTerminal: units)
    }

    /// Reads one run's `state.json`, keeping only units the registry maps to a terminal.
    static func loadState(at stateURL: URL, terminalsByTicket: [String: String]) -> [OrchestrateUnit] {
        guard let data = try? Data(contentsOf: stateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let project = root["project"] as? [String: Any]
        let projectId = project?["id"] as? String ?? ""
        let projectTitle = project?["title"] as? String ?? ""

        guard let rawUnits = root["units"] as? [[String: Any]] else { return [] }
        return rawUnits.compactMap { raw in
            guard let ticket = raw["id"] as? String else { return nil }
            // The registry, not the state file, says which terminal is current.
            guard let terminalId = terminalsByTicket[ticket] else { return nil }
            return OrchestrateUnit(
                ticket: ticket,
                project: projectId,
                projectTitle: projectTitle,
                title: raw["title"] as? String ?? "",
                stage: OrchestrateStage(raw: raw["stage"] as? String ?? ""),
                paused: raw["paused"] as? Bool ?? false,
                gate: raw["gate"] as? String,
                prUrl: raw["prUrl"] as? String,
                terminalId: terminalId
            )
        }
    }
}
