import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("Agent")
struct AgentTests {

    private func loadFixture(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    @Test func decodesFromJSON() throws {
        let data = try loadFixture(named: "sample-agent-working")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let agent = try decoder.decode(Agent.self, from: data)
        #expect(agent.pid == 12345)
        #expect(agent.status == .working)
        #expect(agent.cwd != nil)
        #expect(agent.lastToolUse != nil)
    }

    @Test func decodesWithNulls() throws {
        let json = """
        {
            "session_id": "abc-123",
            "pid": 55555,
            "cwd": null,
            "status": "waiting",
            "updated_at": 9999
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let agent = try decoder.decode(Agent.self, from: Data(json.utf8))
        #expect(agent.sessionId == "abc-123")
        #expect(agent.cwd == nil)
        #expect(agent.lastMessage == nil)
        #expect(agent.lastToolUse == nil)
        #expect(agent.cmuxWorkspace == nil)
        #expect(agent.cmuxSurface == nil)
        #expect(agent.provider == .claudeCode)
    }

    @Test func decodesOpenCodeProvider() throws {
        let json = """
        {
            "provider": "opencode",
            "sessionId": "open-1",
            "pid": 42,
            "cwd": "/tmp",
            "status": "working",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.provider == .openCode)
        #expect(agent.id == "opencode:open-1")
    }

    @Test func directoryLabel() {
        let agent = Agent.fixture(cwd: "/Users/demo/projects/myapp")
        #expect(agent.directoryLabel == "myapp")
    }

    @Test func directoryLabelForDesktop() {
        let agent = Agent.fixture(cwd: nil)
        #expect(agent.directoryLabel == "APP")
    }

    @Test func directoryLabelPrefersAgentType() {
        let agent = Agent.fixture(cwd: "/Users/demo/projects/myapp", agentType: "Reviewer")
        #expect(agent.directoryLabel == "Reviewer")
    }

    @Test func isCmuxSession() {
        let withBoth = Agent.fixture(cmuxWorkspace: "my-workspace", cmuxSurface: "main")
        #expect(withBoth.isCmuxSession == true)

        let withOnlyWorkspace = Agent.fixture(cmuxWorkspace: "my-workspace", cmuxSurface: nil)
        #expect(withOnlyWorkspace.isCmuxSession == false)

        let withNeither = Agent.fixture(cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(withNeither.isCmuxSession == false)
    }

    @Test func parentSessionIdDecodes() throws {
        let json = """
        {
            "sessionId": "child-1",
            "pid": 100,
            "cwd": "/tmp",
            "status": "working",
            "parentSessionId": "parent-1",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.parentSessionId == "parent-1")
    }

    @Test func parentSessionIdDefaultsToNil() throws {
        let json = """
        {
            "sessionId": "child-1",
            "pid": 100,
            "status": "working",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.parentSessionId == nil)
    }

    @Test func taskCompletedAtDecodes() throws {
        let json = """
        {
            "sessionId": "s1",
            "pid": 100,
            "status": "working",
            "taskCompletedAt": 1710000000000,
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.taskCompletedAt == 1710000000000)
    }

    @Test func isTaskJustCompleted() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let recent = Agent.fixture(taskCompletedAt: now - 1000)
        #expect(recent.isTaskJustCompleted == true)

        let old = Agent.fixture(taskCompletedAt: now - 5000)
        #expect(old.isTaskJustCompleted == false)

        let none = Agent.fixture(taskCompletedAt: nil)
        #expect(none.isTaskJustCompleted == false)
    }
}
