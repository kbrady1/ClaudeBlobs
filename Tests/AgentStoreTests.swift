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
        let waiting = Agent.fixture(sessionId: "w", pid: 100, status: .waiting)
        let working = Agent.fixture(sessionId: "k", pid: 101, status: .working)
        let perm = Agent.fixture(sessionId: "p", pid: 102, status: .permission)

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

    @Test func sortsByCreatedAt() throws {
        let oldest = Agent.fixture(sessionId: "a", pid: 200, status: .working, createdAt: 1000, updatedAt: 3000)
        let middle = Agent.fixture(sessionId: "b", pid: 201, status: .permission, createdAt: 2000, updatedAt: 2000)
        let newest = Agent.fixture(sessionId: "c", pid: 202, status: .waiting, createdAt: 3000, updatedAt: 1000)

        for agent in [newest, oldest, middle] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents[0].sessionId == "a")
        #expect(store.agents[1].sessionId == "b")
        #expect(store.agents[2].sessionId == "c")
    }

    @Test func buildsChildRelationshipsFromParentSessionId() throws {
        let parent = Agent.fixture(sessionId: "parent", pid: 200, status: .working, updatedAt: 1000)
        let child = Agent.fixture(sessionId: "child", pid: 201, status: .working, parentSessionId: "parent", updatedAt: 1000)

        for agent in [parent, child] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.childSessionIds["parent"] == ["child"])
        #expect(store.topLevelAgents.count == 1)
        #expect(store.topLevelAgents.first?.sessionId == "parent")
    }
}
