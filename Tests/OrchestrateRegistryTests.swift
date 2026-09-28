import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("OrchestrateRegistry")
struct OrchestrateRegistryTests {
    // MARK: - Fixtures

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a registry plus one run's state file, wired together the way the
    /// daemon writes them.
    @discardableResult
    private func writeRun(
        in dir: URL,
        pid: Int = 4242,
        units: [(ticket: String, stage: String, terminal: String, gate: String?, paused: Bool)]
    ) throws -> URL {
        let stateURL = dir.appendingPathComponent("state.json")
        let state: [String: Any] = [
            "project": ["id": "PLN-3404", "title": "React Native Migration"],
            "units": units.map { unit -> [String: Any] in
                var raw: [String: Any] = [
                    "id": unit.ticket,
                    "title": "Ticket \(unit.ticket)",
                    "stage": unit.stage,
                    "paused": unit.paused,
                    "terminalId": unit.terminal,
                ]
                if let gate = unit.gate { raw["gate"] = gate }
                return raw
            },
        ]
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)

        let registryURL = dir.appendingPathComponent("registry.json")
        let registry: [String: Any] = [
            "orchestrators": [
                stateURL.path: [
                    "statePath": stateURL.path,
                    "pid": pid,
                    "port": 7391,
                    "identity": "default",
                    "unitSessionIds": Dictionary(
                        units.map { ($0.ticket, $0.terminal) },
                        uniquingKeysWith: { a, _ in a }
                    ),
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: registry).write(to: registryURL)
        return registryURL
    }

    /// Fixtures default to epoch 1000, which reads as decades of silence and
    /// surfaces every worker. These tests are about the registry join, so they
    /// use a session that just wrote its status file.
    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func load(_ registryURL: URL, alive: @escaping (Int) -> Bool = { _ in true }) -> OrchestrateSnapshot {
        OrchestrateRegistry.load(registryURL: registryURL, isProcessAlive: alive)
    }

    // MARK: - Decoding

    @Test func joinsUnitsByTerminalId() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])

        let snapshot = load(url)
        let unit = snapshot.unit(forTerminal: "term-a")
        #expect(unit?.ticket == "ENG-17773")
        #expect(unit?.project == "PLN-3404")
        #expect(unit?.projectTitle == "React Native Migration")
        #expect(unit?.stage == .implement)
        #expect(unit?.isDriven == true)
    }

    @Test func unknownTerminalIsNotOrchestrated() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])
        #expect(load(url).unit(forTerminal: "term-somebody-else") == nil)
        #expect(load(url).unit(forTerminal: nil) == nil)
    }

    /// The daemon renamed this stage when the verification gate moved ahead of
    /// the pull request. State files on disk still carry the old name.
    @Test func bothVerifyStageNamesDecodeTheSame() {
        #expect(OrchestrateStage(raw: "verify") == .verify)
        #expect(OrchestrateStage(raw: "implement-done") == .verify)
    }

    /// A stage a newer daemon invents must not leak a worker into the HUD.
    @Test func unknownStageIsStillDriven() {
        let stage = OrchestrateStage(raw: "some-future-stage")
        #expect(stage == .unknown("some-future-stage"))
        #expect(stage.isDriven)
    }

    // MARK: - Liveness

    @Test func deadDaemonHandsItsWorkersBack() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, pid: 999_999, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])
        #expect(load(url, alive: { _ in false }).unitsByTerminal.isEmpty)
        #expect(!load(url, alive: { _ in true }).unitsByTerminal.isEmpty)
    }

    @Test func missingRegistryIsEmptyNotAnError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-registry-\(UUID().uuidString).json")
        #expect(load(missing) == .empty)
    }

    @Test func corruptRegistryIsEmptyNotAnError() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("registry.json")
        try Data("{ not json".utf8).write(to: url)
        #expect(load(url) == .empty)
    }

    /// A registry entry whose state file has been deleted must not crash or
    /// strand the units it named.
    @Test func missingStateFileYieldsNoUnits() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("state.json"))
        #expect(load(url).unitsByTerminal.isEmpty)
    }

    // MARK: - Driven vs handed back

    @Test func terminalStagesHandTheWorkerBack() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-1", "implement", "term-driven", nil, false),
            ("ENG-2", "done", "term-done", nil, false),
            ("ENG-3", "abandoned", "term-abandoned", nil, false),
            ("ENG-4", "review", "term-review", nil, false),
        ])
        let snapshot = load(url)
        #expect(snapshot.unit(forTerminal: "term-driven")?.isDriven == true)
        #expect(snapshot.unit(forTerminal: "term-review")?.isDriven == true)
        #expect(snapshot.unit(forTerminal: "term-done")?.isDriven == false)
        #expect(snapshot.unit(forTerminal: "term-abandoned")?.isDriven == false)
    }

    @Test func pausedUnitComesBackToTheDeveloper() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-1", "implement", "term-a", nil, true),
        ])
        #expect(load(url).unit(forTerminal: "term-a")?.isDriven == false)
    }

    // MARK: - The operator gate

    /// `gate` is the unit's policy for when its gate is eventually reached, not
    /// a signal that a human is needed now. Most units in a run carry
    /// `gate: "operator"` from creation, so reading the policy as the request
    /// put every unit on the board for the whole of its verify stage.
    @Test func gatePolicyAloneDoesNotSurfaceTheWorker() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-1", "verify", "term-gated", "operator", false),
            ("ENG-2", "review", "term-review", "operator", false),
            ("ENG-3", "verify", "term-auto", "auto", false),
            ("ENG-4", "verify", "term-paused", "operator", true),
        ])
        let snapshot = load(url)
        let agent = Agent.fixture(sessionId: "gate-probe", status: .working, supersetTerminal: "term-gated", updatedAt: now)

        func orchestrated(_ terminal: String) -> Bool {
            BoardModel.isOrchestrated(
                agent,
                orchestratedIds: [agent.id],
                optedOutIds: [],
                unit: snapshot.unit(forTerminal: terminal)
            )
        }

        // The orchestrator is still driving these, whatever their gate policy.
        #expect(orchestrated("term-gated"))
        #expect(orchestrated("term-review"))
        #expect(orchestrated("term-auto"))
        // The orchestrator parked this one for a human, so it belongs on the board.
        #expect(!orchestrated("term-paused"))
    }

    /// The daemon omits `gateApproved` until a gate is reached. The absent key
    /// must never read as "a human has not approved yet".
    @Test func unitWithNoGateApprovedKeyStaysHidden() throws {
        let dir = try tempDir("orch-registry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeRun(in: dir, units: [
            ("ENG-17648", "verify", "term-a", "operator", false),
        ])
        let agent = Agent.fixture(sessionId: "no-key", status: .working, supersetTerminal: "term-a", updatedAt: now)
        #expect(BoardModel.isOrchestrated(
            agent,
            orchestratedIds: [agent.id],
            optedOutIds: [],
            unit: load(url).unit(forTerminal: "term-a")
        ))
    }

    // MARK: - AgentStore join

    @Test func storeParksAWorkerTheRegistryClaims() throws {
        let dir = try tempDir("orch-store")
        defer { try? FileManager.default.removeItem(at: dir) }
        let statusDir = dir.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)

        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])
        let store = AgentStore(statusDirectory: statusDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.orchestrateStore = OrchestrateStore(
            registryURL: url, enableWatcher: false, isProcessAlive: { _ in true }
        )

        // A worker in the run's terminal.
        let worker = Agent.fixture(
            sessionId: "worker-a",
            status: .working,
            lastMessage: "Refactored the parser.",
            supersetTerminal: "term-a",
            updatedAt: now
        )
        try JSONEncoder().encode(worker).write(to: statusDir.appendingPathComponent("\(worker.sessionId).json"))
        store.reload()

        #expect(store.isOrchestrated(worker))
        #expect(store.orchestrateUnit(for: worker)?.ticket == "ENG-17773")

        // An unrelated session in the same status directory is untouched.
        let other = Agent.fixture(sessionId: "worker-other", status: .working, supersetTerminal: "term-unrelated", updatedAt: now)
        try JSONEncoder().encode(other).write(to: statusDir.appendingPathComponent("\(other.sessionId).json"))
        store.reload()
        #expect(!store.isOrchestrated(other))
    }

    /// The registry is the authority: once a unit is no longer driven, its
    /// worker is handed back whatever the session is still writing.
    @Test func undrivenUnitHandsTheWorkerBack() throws {
        let dir = try tempDir("orch-store")
        defer { try? FileManager.default.removeItem(at: dir) }
        let statusDir = dir.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)

        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "done", "term-a", nil, false),
        ])
        let store = AgentStore(statusDirectory: statusDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.orchestrateStore = OrchestrateStore(
            registryURL: url, enableWatcher: false, isProcessAlive: { _ in true }
        )

        let worker = Agent.fixture(
            sessionId: "worker-stale",
            status: .working,
            lastMessage: "ORCHESTRATE-STATUS still building",
            supersetTerminal: "term-a",
            updatedAt: now
        )
        try JSONEncoder().encode(worker).write(to: statusDir.appendingPathComponent("\(worker.sessionId).json"))
        store.reload()

        // The unit merged, so the developer gets the worker back.
        #expect(!store.isOrchestrated(worker))
    }

    /// A worker spawned before its daemon registered the terminal is not
    /// orchestrated yet. Its own output does not speak for it.
    @Test func unclaimedWorkerIsNotOrchestrated() throws {
        let dir = try tempDir("orch-store")
        defer { try? FileManager.default.removeItem(at: dir) }
        let statusDir = dir.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)

        let url = try writeRun(in: dir, units: [
            ("ENG-17773", "implement", "term-a", nil, false),
        ])
        let store = AgentStore(statusDirectory: statusDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.orchestrateStore = OrchestrateStore(
            registryURL: url, enableWatcher: false, isProcessAlive: { _ in true }
        )

        let unclaimed = Agent.fixture(
            sessionId: "worker-unclaimed",
            status: .working,
            lastMessage: "ORCHESTRATE-STATUS running the tests",
            supersetTerminal: "term-not-registered-yet",
            updatedAt: now
        )
        try JSONEncoder().encode(unclaimed).write(to: statusDir.appendingPathComponent("\(unclaimed.sessionId).json"))
        store.reload()

        #expect(!store.isOrchestrated(unclaimed))
        #expect(store.orchestrateUnit(for: unclaimed) == nil)
    }
}
