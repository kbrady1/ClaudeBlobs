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
        #expect(store.agents.first?.provider == .claudeCode)
    }

    @Test func loadsAgentsFromMultipleProviders() throws {
        let root = tmpDir.appendingPathComponent("providers")
        let claudeDir = root.appendingPathComponent("claude")
        let openDir = root.appendingPathComponent("opencode")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: openDir, withIntermediateDirectories: true)

        let claudeAgent = Agent.fixture(provider: .claudeCode, sessionId: "c1", pid: 111, status: .waiting)
        let openAgent = Agent.fixture(provider: .openCode, sessionId: "o1", pid: 222, status: .working)
        try JSONEncoder().encode(claudeAgent).write(to: claudeDir.appendingPathComponent("c1.json"))
        try JSONEncoder().encode(openAgent).write(to: openDir.appendingPathComponent("o1.json"))

        let store = AgentStore(
            statusSources: [
                AgentStatusSource(provider: .claudeCode, directoryURL: claudeDir),
                AgentStatusSource(provider: .openCode, directoryURL: openDir),
            ],
            enableWatcher: false,
            isProcessAlive: { _ in true }
        )
        store.reload()

        #expect(store.agents.count == 2)
        #expect(Set(store.agents.map(\.provider)) == Set([.claudeCode, .openCode]))
    }

    @Test func keepsSamePidAcrossProviders() throws {
        let root = tmpDir.appendingPathComponent("same-pid")
        let claudeDir = root.appendingPathComponent("claude")
        let openDir = root.appendingPathComponent("opencode")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: openDir, withIntermediateDirectories: true)

        let claudeAgent = Agent.fixture(provider: .claudeCode, sessionId: "c1", pid: 999, status: .waiting)
        let openAgent = Agent.fixture(provider: .openCode, sessionId: "o1", pid: 999, status: .working)
        try JSONEncoder().encode(claudeAgent).write(to: claudeDir.appendingPathComponent("c1.json"))
        try JSONEncoder().encode(openAgent).write(to: openDir.appendingPathComponent("o1.json"))

        let store = AgentStore(
            statusSources: [
                AgentStatusSource(provider: .claudeCode, directoryURL: claudeDir),
                AgentStatusSource(provider: .openCode, directoryURL: openDir),
            ],
            enableWatcher: false,
            isProcessAlive: { _ in true }
        )
        store.reload()

        #expect(store.agents.map(\.sessionId).sorted() == ["c1", "o1"])
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

        #expect(store.childSessionIds[parent.id] == [child.id])
        #expect(store.topLevelAgents.count == 1)
        #expect(store.topLevelAgents.first?.sessionId == "parent")
    }

    @Test func hidesHeadlessClaudeInvocations() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let interactive = Agent.fixture(sessionId: "interactive", pid: 1001, status: .working, updatedAt: nowMs)
        let headless = Agent.fixture(sessionId: "headless", pid: 2002, status: .working, updatedAt: nowMs)
        let subagent = Agent.fixture(sessionId: "sub", pid: 0, status: .working, parentSessionId: "interactive", updatedAt: nowMs)
        for agent in [interactive, headless, subagent] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(
            statusDirectory: tmpDir,
            enableWatcher: false,
            isProcessAlive: { _ in true },
            isHeadlessInvocation: { pid in pid == 2002 }
        )
        store.reload()

        let ids = Set(store.agents.map(\.sessionId))
        #expect(ids == ["interactive", "sub"])
    }

    @Test func sweepsStaleSubagentAfterParentTransitions() throws {
        // Reported bug: a finished subagent (SubagentStop missed) stays blue
        // because its pid-0 file is stuck at `working`. The parent has resumed
        // its own turn — here into `permission`, not `waiting` — after the
        // child last updated, so the orphaned child must be pruned.
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let parent = Agent.fixture(
            sessionId: "parent", pid: 500, status: .permission,
            updatedAt: nowMs, statusChangedAt: nowMs
        )
        let staleChild = Agent.fixture(
            sessionId: "child", pid: 0, status: .working,
            parentSessionId: "parent", updatedAt: nowMs - 20_000
        )
        for agent in [parent, staleChild] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        let ids = Set(store.agents.map(\.sessionId))
        #expect(ids == ["parent"])
        #expect(store.childSessionIds[parent.id] == nil)
    }

    @Test func keepsActiveSubagentNewerThanParentTransition() throws {
        // Guard the protection invariant: an actively-working child whose
        // updatedAt is newer than the parent's last transition is NOT orphaned,
        // even when the parent briefly sits in `permission`.
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let parent = Agent.fixture(
            sessionId: "parent", pid: 600, status: .permission,
            updatedAt: nowMs - 5_000, statusChangedAt: nowMs - 5_000
        )
        let activeChild = Agent.fixture(
            sessionId: "child", pid: 0, status: .working,
            parentSessionId: "parent", updatedAt: nowMs
        )
        for agent in [parent, activeChild] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.childSessionIds[parent.id] == [activeChild.id])
    }

    @Test func monitorToolUseTracksSessionAndGoesQuietWhenDone() throws {
        let sessionId = "monitor-\(UUID().uuidString)"
        var agent = Agent.fixture(
            sessionId: sessionId, pid: 700, status: .waiting,
            lastToolUse: "Monitor: {\"command\":\"tail -f log\",\"persistent\":true}",
            waitReason: "done"
        )
        try JSONEncoder().encode(agent).write(to: tmpDir.appendingPathComponent("\(sessionId).json"))

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        let loaded = try #require(store.agents.first)
        #expect(store.monitorSessionIds.contains(loaded.id))
        #expect(store.cronIsQuiet(loaded) == true)
        #expect(store.collapsedAgents.isEmpty) // quiet monitor session is auto-hidden

        // A later tool call overwrites lastToolUse, but the session should
        // remain tracked as having an active monitor until TaskStop fires.
        agent.lastToolUse = "Edit: file.swift"
        try JSONEncoder().encode(agent).write(to: tmpDir.appendingPathComponent("\(sessionId).json"))
        store.reload()
        #expect(store.monitorSessionIds.contains(loaded.id))

        agent.lastToolUse = "TaskStop: {\"task_id\":\"abc\"}"
        try JSONEncoder().encode(agent).write(to: tmpDir.appendingPathComponent("\(sessionId).json"))
        store.reload()
        #expect(!store.monitorSessionIds.contains(loaded.id))
    }
}
