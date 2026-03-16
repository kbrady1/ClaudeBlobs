import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("AgentStore")
struct AgentStoreTests {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hud-store-test-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    @Test func loadsAgentsFromDirectory() throws {
        let agent = Agent.fixture(sessionId: "s1", status: .waiting)
        let data = try JSONEncoder().encode(agent)
        try data.write(to: tmpDir.appendingPathComponent("s1.json"))

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents.count == 1)
        #expect(store.agents.first?.sessionId == "s1")
    }

    @Test func filtersCollapsedAgents() throws {
        let waiting = Agent.fixture(sessionId: "w", status: .waiting)
        let working = Agent.fixture(sessionId: "k", status: .working)
        let perm = Agent.fixture(sessionId: "p", status: .permission)

        for agent in [waiting, working, perm] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.collapsedAgents.count == 2) // waiting + permission
        #expect(store.agents.count == 3)
    }

    @Test func handlesCorruptedFiles() throws {
        try "not json".write(
            to: tmpDir.appendingPathComponent("bad.json"),
            atomically: true, encoding: .utf8
        )

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents.isEmpty)
    }

    @Test func sortsByStatusPriority() throws {
        let working = Agent.fixture(sessionId: "w", status: .working)
        let waiting = Agent.fixture(sessionId: "a", status: .waiting)
        let perm = Agent.fixture(sessionId: "p", status: .permission)

        for agent in [working, waiting, perm] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents[0].status == .permission)
        #expect(store.agents[1].status == .waiting)
        #expect(store.agents[2].status == .working)
    }
}
