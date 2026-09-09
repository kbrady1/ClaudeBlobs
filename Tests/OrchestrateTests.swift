import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("Orchestrate")
struct OrchestrateTests {
    private func worker(
        lastMessage: String? = nil,
        toolFailure: String? = nil,
        ageSeconds: TimeInterval = 0
    ) -> Agent {
        let now = Date().timeIntervalSince1970
        return Agent.fixture(
            status: .working,
            lastMessage: lastMessage,
            toolFailure: toolFailure,
            updatedAt: Int64((now - ageSeconds) * 1000)
        )
    }

    // MARK: - Sentinel parsing

    @Test func parsesEachSentinel() {
        #expect(OrchestrateReport.parse("ORCHESTRATE-STATUS running the tests")
            == OrchestrateReport(sentinel: .status, detail: "running the tests"))
        #expect(OrchestrateReport.parse("ORCHESTRATE-BLOCKED no Android SDK")?.sentinel == .blocked)
        #expect(OrchestrateReport.parse("ORCHESTRATE-QUESTION which AVD?")?.sentinel == .question)
        #expect(OrchestrateReport.parse("ORCHESTRATE-PLAN-READY /tmp/plan.md")?.sentinel == .planReady)
        #expect(OrchestrateReport.parse("ORCHESTRATE-PR https://github.com/x/y/pull/1")?.sentinel == .pr)
        #expect(OrchestrateReport.parse("ORCHESTRATE-DONE shipped")?.sentinel == .done)
    }

    @Test func planReadyWinsOverPrefixMatch() {
        #expect(OrchestrateReport.parse("ORCHESTRATE-PLAN-READY /tmp/plan.md")?.detail == "/tmp/plan.md")
    }

    @Test func ignoresUnknownToken() {
        #expect(OrchestrateReport.parse("ORCHESTRATE-PRIVATE something") == nil)
        #expect(OrchestrateReport.parse("no sentinel here") == nil)
    }

    @Test func takesLastSentinelAndStripsDecoration() {
        let text = """
        ORCHESTRATE-STATUS reading the ticket
        Some prose in between.
        **ORCHESTRATE-STATUS opening the pull request**
        """
        #expect(OrchestrateReport.parse(text)?.detail == "opening the pull request")
    }

    // MARK: - Per-turn verdict

    @Test func sentinelTurnMarksTheSessionOrchestrated() {
        #expect(BoardModel.orchestrateVerdict(for: worker(lastMessage: "ORCHESTRATE-STATUS building")) == true)
    }

    @Test func blockedTurnHandsTheSessionBack() {
        #expect(BoardModel.orchestrateVerdict(for: worker(lastMessage: "ORCHESTRATE-BLOCKED no SDK")) == false)
    }

    @Test func turnWithoutASentinelHandsTheSessionBack() {
        #expect(BoardModel.orchestrateVerdict(for: worker(lastMessage: "Refactored the parser.")) == false)
    }

    @Test func clearedMessageCarriesNoVerdict() {
        #expect(BoardModel.orchestrateVerdict(for: worker()) == nil)
    }

    // MARK: - Column placement

    private func isOrchestrated(_ agent: Agent, optedOut: Set<String> = []) -> Bool {
        BoardModel.isOrchestrated(
            agent,
            orchestratedIds: [agent.id],
            optedOutIds: optedOut,
            silenceThreshold: 30 * 60
        )
    }

    @Test func workingWorkerParksInOrchestratedColumn() {
        let agent = worker(lastMessage: "ORCHESTRATE-STATUS running the tests")
        #expect(isOrchestrated(agent))
        #expect(BoardModel.column(
            for: agent, effectiveStatus: .working, isSnoozed: false,
            isClockBearing: false, isOrchestrated: true
        ) == .orchestrated)
    }

    @Test func questionStaysWithTheOrchestrator() {
        #expect(isOrchestrated(worker(lastMessage: "ORCHESTRATE-QUESTION which AVD should I name?")))
    }

    @Test func blockedSurfaces() {
        #expect(!isOrchestrated(worker(lastMessage: "ORCHESTRATE-BLOCKED the worktree is gone")))
    }

    @Test func doneSurfaces() {
        #expect(!isOrchestrated(worker(lastMessage: "ORCHESTRATE-DONE shipped")))
    }

    @Test func toolFailureSurfaces() {
        #expect(!isOrchestrated(worker(lastMessage: "ORCHESTRATE-STATUS building", toolFailure: "error")))
    }

    @Test func silenceSurfaces() {
        let quiet = worker(lastMessage: "ORCHESTRATE-STATUS building", ageSeconds: 31 * 60)
        #expect(!isOrchestrated(quiet))
        let recent = worker(lastMessage: "ORCHESTRATE-STATUS building", ageSeconds: 5 * 60)
        #expect(isOrchestrated(recent))
    }

    @Test func optOutSurfaces() {
        let agent = worker(lastMessage: "ORCHESTRATE-STATUS building")
        #expect(!isOrchestrated(agent, optedOut: [agent.id]))
    }

    @Test func snoozeWinsOverOrchestrated() {
        let agent = worker(lastMessage: "ORCHESTRATE-STATUS building")
        #expect(BoardModel.column(
            for: agent, effectiveStatus: .working, isSnoozed: true,
            isClockBearing: false, isOrchestrated: true
        ) == .snoozed)
    }

    // MARK: - Store tracking across turns

    private func store(in dir: URL) -> AgentStore {
        AgentStore(statusDirectory: dir, enableWatcher: false, isProcessAlive: { _ in true })
    }

    private func write(_ agent: Agent, to dir: URL) throws {
        try JSONEncoder().encode(agent).write(to: dir.appendingPathComponent("\(agent.sessionId).json"))
    }

    @Test func aToolCallKeepsTheVerdictButAPlainTurnClearsIt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchestrate-turns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = store(in: dir)

        let reporting = worker(lastMessage: "ORCHESTRATE-STATUS running the tests")
        try write(reporting, to: dir)
        store.reload()
        #expect(store.isOrchestrated(reporting))

        // Mid-turn: the hooks nulled the message. The verdict must hold.
        let midTurn = worker()
        try write(midTurn, to: dir)
        store.reload()
        #expect(store.isOrchestrated(midTurn))

        // A turn with no sentinel hands the session back for good.
        let plain = worker(lastMessage: "Refactored the parser.")
        try write(plain, to: dir)
        store.reload()
        #expect(!store.isOrchestrated(plain))

        try write(midTurn, to: dir)
        store.reload()
        #expect(!store.isOrchestrated(midTurn))
    }

    @Test func doneStaysClearedAfterTheSentinelIsGone() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchestrate-done-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = store(in: dir)

        try write(worker(lastMessage: "ORCHESTRATE-STATUS building"), to: dir)
        store.reload()

        let done = worker(lastMessage: "ORCHESTRATE-DONE shipped")
        try write(done, to: dir)
        store.reload()
        #expect(!store.isOrchestrated(done))

        // The next tool call clears the message; the session must stay surfaced.
        let after = worker()
        try write(after, to: dir)
        store.reload()
        #expect(!store.isOrchestrated(after))
    }

    @Test func buildPlacesWorkerCardWithItsReport() {
        let agent = worker(lastMessage: "ORCHESTRATE-STATUS running the tests")
        let columns = BoardModel.build(
            agents: [agent],
            children: { _ in [] },
            snoozedIds: [],
            snoozedAt: [:],
            snoozeUntil: [:],
            cronSessionIds: [],
            dismissedClockIds: [],
            orchestratedIds: [agent.id],
            orchestrateOptedOutIds: [],
            passesFilter: { _ in true }
        )
        let cards = columns.first { $0.column == .orchestrated }?.cards ?? []
        #expect(cards.count == 1)
        #expect(cards.first?.orchestrateReport?.detail == "running the tests")
    }
}
