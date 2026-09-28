import SwiftUI

enum BoardColumn: String, CaseIterable, Identifiable {
    case idle
    case needsAttention
    case working
    case monitoring
    case orchestrated
    case snoozed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .needsAttention: return "Needs Attention"
        case .working: return "Working"
        case .monitoring: return "Monitoring"
        case .orchestrated: return "Orchestrated"
        case .snoozed: return "Snoozed"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "zzz"
        case .needsAttention: return "exclamationmark.bubble.fill"
        case .working: return "hammer.fill"
        case .monitoring: return "clock.fill"
        case .orchestrated: return BoardColumn.orchestratedSymbol
        case .snoozed: return "moon.fill"
        }
    }

    func color(theme: ColorTheme) -> Color {
        switch self {
        case .idle: return theme.color(for: .waiting).opacity(0.8)
        case .needsAttention: return theme.color(for: .permission)
        case .working: return theme.color(for: .working)
        case .monitoring: return theme.color(for: .compacting)
        case .orchestrated: return Color(red: 0.44, green: 0.62, blue: 0.98)
        case .snoozed: return Color(white: 0.55)
        }
    }

    /// Accent icon for orchestrated worker sessions, shared by the column
    /// header, the board card, and the blob badge.
    static let orchestratedSymbol = "link"
}

struct BoardCard: Identifiable, Equatable {
    let agent: Agent
    let column: BoardColumn
    let effectiveStatus: AgentStatus
    let enteredAt: Date
    let children: [Agent]
    let isClockBearing: Bool
    let snoozeUntil: Date?
    /// Snoozed until a manual wake. A status change does not end the snooze.
    var isSnoozedIndefinitely: Bool = false
    /// The `/orchestrate` unit driving this session, when a live run claims it.
    var orchestrateUnit: OrchestrateUnit? = nil
    /// Whether an orchestrator is driving this session, even when it has been
    /// pulled out of the orchestrated column. Drives the hand-back button.
    var isOrchestrateWorker: Bool = false

    var id: String { agent.id }
}

struct BoardColumnData: Identifiable, Equatable {
    let column: BoardColumn
    let cards: [BoardCard]
    let hiddenCount: Int

    var id: BoardColumn { column }
}

enum BoardModel {
    static func column(
        for agent: Agent,
        effectiveStatus: AgentStatus,
        isSnoozed: Bool,
        isClockBearing: Bool,
        isOrchestrated: Bool = false
    ) -> BoardColumn {
        if isSnoozed { return .snoozed }
        if isOrchestrated { return .orchestrated }
        switch effectiveStatus {
        case .permission:
            return .needsAttention
        case .waiting:
            if !agent.isDone || agent.toolFailure != nil || agent.isAPIError { return .needsAttention }
            return isClockBearing ? .monitoring : .idle
        case .working, .starting, .compacting, .delegating:
            return .working
        }
    }

    /// Whether the board should park this session in the orchestrated column:
    /// an `/orchestrate` run is driving it, the developer has not opted it out,
    /// and it does not currently need a human.
    ///
    /// `orchestratedIds` comes from `AgentStore`, which joins the run's own
    /// shared state onto each session by Superset terminal id. It cannot be
    /// derived from an `Agent` alone — the session file says nothing about who
    /// is driving the session.
    ///
    /// `unit` is that run's record for this session, when one exists. A paused
    /// unit is the one case where an orchestrated worker is waiting on the
    /// developer specifically: the orchestrator parks a unit it wants a human
    /// to decide, and records why in `pauseReason`.
    ///
    /// The unit's `gate` is deliberately not read here. `gate` is the unit's
    /// policy for when its gate is eventually reached, not a live request —
    /// most units in a run carry `gate: "operator"` from creation, including
    /// units that already finished. Treating the policy as the request put
    /// every unit on the board for the whole of its verify stage.
    ///
    /// `effectiveStatus` keeps a worker that is asking for permission on the
    /// board. An orchestrator cannot answer a permission prompt, so hiding a
    /// red session would stall the run with nothing on screen to explain it.
    ///
    /// Nothing the worker says in its own output is read here. The orchestrator
    /// answers the worker, so a worker that claims to be blocked stays hidden;
    /// only silence past `silenceThreshold` hands it back to the developer.
    static func isOrchestrated(
        _ agent: Agent,
        orchestratedIds: Set<String>,
        optedOutIds: Set<String>,
        unit: OrchestrateUnit? = nil,
        effectiveStatus: AgentStatus? = nil,
        now: Date = Date(),
        silenceThreshold: TimeInterval = Agent.orchestrateSilenceThreshold
    ) -> Bool {
        if optedOutIds.contains(agent.id) { return false }
        guard orchestratedIds.contains(agent.id) else { return false }
        // A permission prompt needs the developer: the orchestrator has no way
        // to approve it.
        if (effectiveStatus ?? agent.status) == .permission { return false }
        // The orchestrator parks a unit it wants a human to decide, so a paused
        // unit comes back to the developer. A unit the orchestrator is still
        // driving is never waiting on the developer.
        if let unit, unit.paused { return false }
        return !agent.orchestrateNeedsHuman(now: now, silenceThreshold: silenceThreshold)
    }

    static func isClockBearing(_ agent: Agent, cronSessionIds: Set<String>, dismissedClockIds: Set<String>) -> Bool {
        if dismissedClockIds.contains(agent.id) { return false }
        return cronSessionIds.contains(agent.id) || agent.isScheduledWakeup || agent.isMonitorActive
    }

    static func build(
        agents: [Agent],
        children: (String) -> [Agent],
        snoozedIds: Set<String>,
        snoozedAt: [String: Date],
        snoozeUntil: [String: Date],
        indefiniteSnoozeIds: Set<String> = [],
        cronSessionIds: Set<String>,
        dismissedClockIds: Set<String>,
        orchestratedIds: Set<String> = [],
        orchestrateOptedOutIds: Set<String> = [],
        orchestrateUnits: [String: OrchestrateUnit] = [:],
        now: Date = Date(),
        passesFilter: (Agent) -> Bool
    ) -> [BoardColumnData] {
        var cards: [BoardColumn: [BoardCard]] = [:]
        var hidden: [BoardColumn: Int] = [:]

        for agent in agents {
            let kids = children(agent.id)
            let effective = Agent.effectiveStatus(of: agent, children: kids)
            let snoozed = snoozedIds.contains(agent.id)
            let clock = isClockBearing(agent, cronSessionIds: cronSessionIds, dismissedClockIds: dismissedClockIds)
            let unit = orchestrateUnits[agent.id]
            let orchestrated = isOrchestrated(
                agent,
                orchestratedIds: orchestratedIds,
                optedOutIds: orchestrateOptedOutIds,
                unit: unit,
                effectiveStatus: effective,
                now: now
            )
            let column = column(
                for: agent,
                effectiveStatus: effective,
                isSnoozed: snoozed,
                isClockBearing: clock,
                isOrchestrated: orchestrated
            )

            guard passesFilter(agent) else {
                hidden[column, default: 0] += 1
                continue
            }

            let enteredMs = agent.statusChangedAt ?? agent.createdAt ?? agent.updatedAt
            var enteredAt = Date(timeIntervalSince1970: TimeInterval(enteredMs) / 1000)
            if snoozed, let at = snoozedAt[agent.id] { enteredAt = at }

            cards[column, default: []].append(BoardCard(
                agent: agent,
                column: column,
                effectiveStatus: effective,
                enteredAt: enteredAt,
                children: kids,
                isClockBearing: clock,
                snoozeUntil: snoozeUntil[agent.id],
                isSnoozedIndefinitely: indefiniteSnoozeIds.contains(agent.id),
                orchestrateUnit: unit,
                isOrchestrateWorker: orchestratedIds.contains(agent.id)
            ))
        }

        return BoardColumn.allCases.map { column in
            let sorted = (cards[column] ?? []).sorted { a, b in
                if a.enteredAt != b.enteredAt { return a.enteredAt < b.enteredAt }
                return a.agent.id < b.agent.id
            }
            return BoardColumnData(column: column, cards: sorted, hiddenCount: hidden[column] ?? 0)
        }
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 { return remMinutes == 0 ? "\(hours)h" : "\(hours)h \(remMinutes)m" }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days)d" : "\(days)d \(remHours)h"
    }

    static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        var text = path
        if text.hasPrefix(home) { text = "~" + text.dropFirst(home.count) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count > 4 {
            return "…/" + parts.suffix(3).joined(separator: "/")
        }
        return text
    }
}
