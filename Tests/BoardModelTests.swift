import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("BoardModel")
struct BoardModelTests {
    private func column(
        _ agent: Agent,
        effective: AgentStatus? = nil,
        snoozed: Bool = false,
        clock: Bool = false
    ) -> BoardColumn {
        BoardModel.column(
            for: agent,
            effectiveStatus: effective ?? agent.status,
            isSnoozed: snoozed,
            isClockBearing: clock
        )
    }

    @Test func columnOrderMatchesSpec() {
        #expect(BoardColumn.allCases == [.idle, .needsAttention, .working, .monitoring, .snoozed])
    }

    @Test func snoozedWinsOverEverything() {
        let agent = Agent.fixture(status: .permission)
        #expect(column(agent, snoozed: true) == .snoozed)
    }

    @Test func permissionNeedsAttention() {
        #expect(column(Agent.fixture(status: .permission)) == .needsAttention)
    }

    @Test func waitingQuestionNeedsAttention() {
        let agent = Agent.fixture(status: .waiting, waitReason: "question")
        #expect(column(agent) == .needsAttention)
    }

    @Test func waitingDoneIsIdle() {
        let agent = Agent.fixture(status: .waiting, waitReason: "done")
        #expect(column(agent) == .idle)
    }

    @Test func waitingDoneWithClockIsMonitoring() {
        let agent = Agent.fixture(status: .waiting, waitReason: "done")
        #expect(column(agent, clock: true) == .monitoring)
    }

    @Test func waitingDoneWithFailureNeedsAttention() {
        let agent = Agent.fixture(status: .waiting, waitReason: "done", toolFailure: "error")
        #expect(column(agent, clock: true) == .needsAttention)
    }

    @Test func apiErrorNeedsAttention() {
        let agent = Agent.fixture(status: .waiting, lastMessage: "API Error: overloaded", waitReason: "done")
        #expect(column(agent) == .needsAttention)
    }

    @Test("active statuses are Working", arguments: [AgentStatus.working, .starting, .compacting, .delegating])
    func activeStatusesAreWorking(status: AgentStatus) {
        #expect(column(Agent.fixture(status: status)) == .working)
    }

    @Test func effectiveStatusFromChildrenIsUsed() {
        let parent = Agent.fixture(status: .waiting, waitReason: "done")
        #expect(column(parent, effective: .permission) == .needsAttention)
    }

    @Test func clockBearingRespectsDismissedClock() {
        let agent = Agent.fixture(sessionId: "s", monitorActive: true)
        #expect(BoardModel.isClockBearing(agent, cronSessionIds: [], dismissedClockIds: []))
        #expect(!BoardModel.isClockBearing(agent, cronSessionIds: [], dismissedClockIds: [agent.id]))
        let cron = Agent.fixture(sessionId: "c")
        #expect(BoardModel.isClockBearing(cron, cronSessionIds: [cron.id], dismissedClockIds: []))
    }

    @Test func buildSortsOldestFirstWithinColumn() {
        let old = Agent.fixture(sessionId: "old", status: .working, updatedAt: 5000, statusChangedAt: 1000)
        let new = Agent.fixture(sessionId: "new", status: .working, updatedAt: 5000, statusChangedAt: 4000)
        let mid = Agent.fixture(sessionId: "mid", status: .working, updatedAt: 5000, statusChangedAt: 2000)

        let columns = BoardModel.build(
            agents: [new, old, mid],
            children: { _ in [] },
            snoozedIds: [], snoozedAt: [:], snoozeUntil: [:],
            cronSessionIds: [], dismissedClockIds: [],
            passesFilter: { _ in true }
        )
        let working = columns.first { $0.column == .working }!
        #expect(working.cards.map(\.agent.sessionId) == ["old", "mid", "new"])
        #expect(columns.count == BoardColumn.allCases.count)
    }

    @Test func buildUsesSnoozeStartForSnoozedCards() {
        let agent = Agent.fixture(sessionId: "z", status: .working, statusChangedAt: 1000)
        let snoozeStart = Date(timeIntervalSince1970: 500)
        let columns = BoardModel.build(
            agents: [agent],
            children: { _ in [] },
            snoozedIds: [agent.id], snoozedAt: [agent.id: snoozeStart], snoozeUntil: [agent.id: Date(timeIntervalSince1970: 9000)],
            cronSessionIds: [], dismissedClockIds: [],
            passesFilter: { _ in true }
        )
        let snoozed = columns.first { $0.column == .snoozed }!
        #expect(snoozed.cards.count == 1)
        #expect(snoozed.cards[0].enteredAt == snoozeStart)
        #expect(snoozed.cards[0].snoozeUntil == Date(timeIntervalSince1970: 9000))
    }

    @Test func buildCountsFilteredCards() {
        let shown = Agent.fixture(sessionId: "shown", status: .working)
        let hidden = Agent.fixture(sessionId: "hidden", status: .working)
        let columns = BoardModel.build(
            agents: [shown, hidden],
            children: { _ in [] },
            snoozedIds: [], snoozedAt: [:], snoozeUntil: [:],
            cronSessionIds: [], dismissedClockIds: [],
            passesFilter: { $0.sessionId == "shown" }
        )
        let working = columns.first { $0.column == .working }!
        #expect(working.cards.map(\.agent.sessionId) == ["shown"])
        #expect(working.hiddenCount == 1)
    }

    @Test func formatElapsed() {
        #expect(BoardModel.formatElapsed(42) == "42s")
        #expect(BoardModel.formatElapsed(5 * 60 + 10) == "5m")
        #expect(BoardModel.formatElapsed(3600) == "1h")
        #expect(BoardModel.formatElapsed(3600 + 12 * 60) == "1h 12m")
        #expect(BoardModel.formatElapsed(2 * 86400 + 3 * 3600) == "2d 3h")
        #expect(BoardModel.formatElapsed(-5) == "0s")
    }

    @Test func shortPath() {
        #expect(BoardModel.shortPath("/Users/me/SourceCode/app", home: "/Users/me") == "~/SourceCode/app")
        #expect(BoardModel.shortPath("/Users/me/a/b/c/d/e", home: "/Users/me") == "…/c/d/e")
        #expect(BoardModel.shortPath("/tmp/x", home: "/Users/me") == "/tmp/x")
    }
}
