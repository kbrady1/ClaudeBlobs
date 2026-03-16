import Testing
import Foundation
@testable import ClaudeAgentHUDLib

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
    }

    @Test func directoryLabel() {
        let agent = Agent.fixture(cwd: "/Users/kent/projects/myapp")
        #expect(agent.directoryLabel == "myapp")
    }

    @Test func directoryLabelForDesktop() {
        let agent = Agent.fixture(cwd: nil)
        #expect(agent.directoryLabel == "APP")
    }

    @Test func directoryLabelPrefersAgentType() {
        let agent = Agent.fixture(cwd: "/Users/kent/projects/myapp", agentType: "Reviewer")
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
}
