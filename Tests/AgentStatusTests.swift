import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("AgentStatus")
struct AgentStatusTests {

    @Test func decodesFromJSON() throws {
        let json = #""waiting""#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AgentStatus.self, from: data)
        #expect(decoded == .waiting)
    }

    @Test func allCasesHaveColor() {
        for status in AgentStatus.allCases {
            let description = "\(status.color)"
            #expect(!description.isEmpty)
        }
    }

    @Test func visibleInCollapsed() {
        #expect(AgentStatus.waiting.visibleWhenCollapsed == true)
        #expect(AgentStatus.permission.visibleWhenCollapsed == true)
        #expect(AgentStatus.starting.visibleWhenCollapsed == true)
        #expect(AgentStatus.working.visibleWhenCollapsed == false)
        #expect(AgentStatus.compacting.visibleWhenCollapsed == false)
    }

    @Test func compactingStatus() {
        let status = AgentStatus.compacting
        #expect(status.displayName == "Compacting")
        #expect(status.visibleWhenCollapsed == false)
    }

    @Test func speechBubbleText() {
        let waiting = Agent.fixture(
            status: .waiting,
            lastMessage: "What should I do?",
            lastToolUse: nil
        )
        #expect(waiting.speechBubbleText == "What should I do?")

        let working = Agent.fixture(
            status: .working,
            lastMessage: nil,
            lastToolUse: "Bash"
        )
        #expect(working.speechBubbleText == "Bash")

        let permission = Agent.fixture(
            status: .permission,
            lastMessage: nil,
            lastToolUse: "rm -rf /tmp"
        )
        #expect(permission.speechBubbleText == "Wants to run: rm -rf /tmp")

        let permissionNoTool = Agent.fixture(
            status: .permission,
            lastMessage: nil,
            lastToolUse: nil
        )
        #expect(permissionNoTool.speechBubbleText == "")

        let starting = Agent.fixture(status: .starting)
        #expect(starting.speechBubbleText == "Starting up...")
    }
}
