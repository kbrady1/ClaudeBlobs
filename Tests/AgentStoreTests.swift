import Testing
import Foundation
@testable import ClaudeBlobsLib

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
        store.hideWorkingAgents = false
        store.reload()

        #expect(store.collapsedAgents.count == 3) // all agents visible by default
        #expect(store.agents.count == 3)

        store.hideWorkingAgents = true
        #expect(store.collapsedAgents.count == 2) // waiting + permission only
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

    @Test func sortByPriorityReordersCollapsedAgents() throws {
        // Create agents: oldest=working(blue), middle=waiting(orange), newest=permission(red)
        let oldest = Agent.fixture(sessionId: "a", pid: 300, status: .working, createdAt: 1000, updatedAt: 1000)
        let middle = Agent.fixture(sessionId: "b", pid: 301, status: .waiting, createdAt: 2000, updatedAt: 2000)
        let newest = Agent.fixture(sessionId: "c", pid: 302, status: .permission, createdAt: 3000, updatedAt: 3000)

        for agent in [oldest, middle, newest] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.hideWorkingAgents = false
        store.sortByPriority = false
        store.reload()

        // Default: sorted by age (oldest first)
        #expect(store.collapsedAgents.map(\.sessionId) == ["a", "b", "c"])

        // Priority sort: red(permission), orange(waiting), blue(working)
        store.sortByPriority = true
        #expect(store.collapsedAgents.map(\.sessionId) == ["c", "b", "a"])
    }

    @Test func sortByPriorityStableWithinSameStatus() throws {
        let older = Agent.fixture(sessionId: "x", pid: 400, status: .waiting, createdAt: 1000, updatedAt: 1000)
        let newer = Agent.fixture(sessionId: "y", pid: 401, status: .waiting, createdAt: 2000, updatedAt: 2000)

        for agent in [older, newer] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.sortByPriority = true
        store.reload()

        // Same status: newer (more recently updated) agent first (leftmost)
        #expect(store.collapsedAgents.map(\.sessionId) == ["y", "x"])
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
