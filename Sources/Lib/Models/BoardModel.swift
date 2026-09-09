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
    /// The worker's last sentinel, for cards in the orchestrated column.
    var orchestrateReport: OrchestrateReport? = nil
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
    /// its last turn reported to an orchestrator, the developer has not opted
    /// it out, and it does not currently need a human.
    ///
    /// `orchestratedIds` comes from `AgentStore`, which reads the verdict off
    /// each turn as it lands. It cannot be derived from an `Agent` alone: the
    /// hooks null the message on every tool call, so a session mid-turn is
    /// carrying no sentinel even while an orchestrator drives it.
    static func isOrchestrated(
        _ agent: Agent,
        orchestratedIds: Set<String>,
        optedOutIds: Set<String>,
        now: Date = Date(),
        silenceThreshold: TimeInterval = Agent.orchestrateSilenceThreshold
    ) -> Bool {
        if optedOutIds.contains(agent.id) { return false }
        guard orchestratedIds.contains(agent.id) else { return false }
        return !agent.orchestrateNeedsHuman(now: now, silenceThreshold: silenceThreshold)
    }

    /// The verdict a single turn carries. `nil` means the turn said nothing —
    /// the hooks cleared the message for a tool call — so the session keeps
    /// whatever it was.
    static func orchestrateVerdict(for agent: Agent) -> Bool? {
        if let report = agent.orchestrateReport { return !report.sentinel.needsHuman }
        return agent.hasCurrentMessage ? false : nil
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
        cronSessionIds: Set<String>,
        dismissedClockIds: Set<String>,
        orchestratedIds: Set<String> = [],
        orchestrateOptedOutIds: Set<String> = [],
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
            let orchestrated = isOrchestrated(
                agent,
                orchestratedIds: orchestratedIds,
                optedOutIds: orchestrateOptedOutIds,
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
                orchestrateReport: agent.orchestrateReport,
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
