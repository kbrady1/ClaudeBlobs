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

    // MARK: - Column placement

    private func isOrchestrated(
        _ agent: Agent,
        optedOut: Set<String> = [],
        effectiveStatus: AgentStatus? = nil
    ) -> Bool {
        BoardModel.isOrchestrated(
            agent,
            orchestratedIds: [agent.id],
            optedOutIds: optedOut,
            effectiveStatus: effectiveStatus,
            silenceThreshold: 60 * 60
        )
    }

    @Test func permissionSurfaces() {
        let asking = Agent.fixture(status: .permission)
        #expect(!isOrchestrated(asking))
    }

    /// A worker whose child subagent is asking for permission surfaces too:
    /// the effective status carries the child's prompt up to the parent.
    @Test func childPermissionSurfaces() {
        #expect(!isOrchestrated(worker(), effectiveStatus: .permission))
    }

    @Test func permissionWorkerLandsInNeedsAttention() {
        let asking = Agent.fixture(status: .permission)
        let columns = BoardModel.build(
            agents: [asking],
            children: { _ in [] },
            snoozedIds: [], snoozedAt: [:], snoozeUntil: [:],
            cronSessionIds: [], dismissedClockIds: [],
            orchestratedIds: [asking.id],
            passesFilter: { _ in true }
        )
        let card = columns.flatMap(\.cards).first { $0.agent.id == asking.id }
        #expect(card?.column == .needsAttention)
        #expect(card?.isOrchestrateWorker == true)
    }

    @Test func workingWorkerParksInOrchestratedColumn() {
        let agent = worker()
        #expect(isOrchestrated(agent))
        #expect(BoardModel.column(
            for: agent, effectiveStatus: .working, isSnoozed: false,
            isClockBearing: false, isOrchestrated: true
        ) == .orchestrated)
    }

    /// The orchestrator answers its own workers, so nothing a worker writes in
    /// its message pulls it back onto the board.
    @Test func workerOutputNeverSurfacesTheSession() {
        #expect(isOrchestrated(worker(lastMessage: "ORCHESTRATE-BLOCKED the worktree is gone")))
        #expect(isOrchestrated(worker(lastMessage: "ORCHESTRATE-DONE shipped")))
        #expect(isOrchestrated(worker(lastMessage: "Refactored the parser.")))
    }

    /// A failed tool is the worker's problem to report to its orchestrator.
    @Test func toolFailureStaysWithTheOrchestrator() {
        #expect(isOrchestrated(worker(toolFailure: "error")))
    }

    @Test func silenceSurfaces() {
        #expect(!isOrchestrated(worker(ageSeconds: 61 * 60)))
        #expect(isOrchestrated(worker(ageSeconds: 45 * 60)))
    }

    @Test func silenceThresholdDefaultsToAnHour() {
        UserDefaults.standard.removeObject(forKey: "orchestrateSilenceMinutes")
        #expect(Agent.orchestrateSilenceThreshold == 60 * 60)
    }

    /// The card reads `isOrchestrateWorker` to keep the orchestrated marker on
    /// a worker the silence clock pushed into a normal column.
    @Test func surfacedWorkerStaysMarkedAsAWorker() {
        let quiet = worker(ageSeconds: 61 * 60)
        let columns = BoardModel.build(
            agents: [quiet],
            children: { _ in [] },
            snoozedIds: [], snoozedAt: [:], snoozeUntil: [:],
            cronSessionIds: [], dismissedClockIds: [],
            orchestratedIds: [quiet.id],
            passesFilter: { _ in true }
        )
        let card = columns.flatMap(\.cards).first { $0.agent.id == quiet.id }
        #expect(card?.column != .orchestrated)
        #expect(card?.isOrchestrateWorker == true)
    }

    @Test func optOutSurfaces() {
        let agent = worker()
        #expect(!isOrchestrated(agent, optedOut: [agent.id]))
    }

    @Test func snoozeWinsOverOrchestrated() {
        #expect(BoardModel.column(
            for: worker(), effectiveStatus: .working, isSnoozed: true,
            isClockBearing: false, isOrchestrated: true
        ) == .snoozed)
    }

    // MARK: - Store tracking

    private func store(in dir: URL) -> AgentStore {
        AgentStore(statusDirectory: dir, enableWatcher: false, isProcessAlive: { _ in true })
    }

    private func write(_ agent: Agent, to dir: URL) throws {
        try JSONEncoder().encode(agent).write(to: dir.appendingPathComponent("\(agent.sessionId).json"))
    }

    /// Without a registry claiming the terminal, no session is orchestrated —
    /// whatever the session's own message says.
    @Test func registryIsTheOnlySourceOfTruth() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchestrate-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = store(in: dir)

        let reporting = worker(lastMessage: "ORCHESTRATE-STATUS running the tests")
        try write(reporting, to: dir)
        store.reload()
        #expect(!store.isOrchestrated(reporting))
    }

    @Test func buildPlacesWorkerCardInTheOrchestratedColumn() {
        let agent = worker()
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
        #expect(cards.first?.agent.id == agent.id)
    }
}
