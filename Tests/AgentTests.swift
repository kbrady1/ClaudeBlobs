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

    @Test func rawLastMessageDecodes() throws {
        let json = """
        {
            "sessionId": "raw-msg-1",
            "pid": 100,
            "status": "waiting",
            "waitReason": "done",
            "rawLastMessage": "I've completed the task.",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.rawLastMessage == "I've completed the task.")
    }

    @Test func rawLastMessageDefaultsToNil() throws {
        let json = """
        {
            "sessionId": "raw-msg-2",
            "pid": 100,
            "status": "waiting",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.rawLastMessage == nil)
    }

    @Test func fixtureRawLastMessage() {
        let withMsg = Agent.fixture(rawLastMessage: "test message")
        #expect(withMsg.rawLastMessage == "test message")

        let withoutMsg = Agent.fixture()
        #expect(withoutMsg.rawLastMessage == nil)
    }

    @Test func isGithubToolWithNewFormat() {
        // New human-readable format: "Bash: git push"
        let gitPush = Agent.fixture(lastToolUse: "Bash: git push origin main")
        #expect(gitPush.isGithubTool == true)

        let ghPr = Agent.fixture(lastToolUse: "Bash: gh pr create")
        #expect(ghPr.isGithubTool == true)

        let gitBare = Agent.fixture(lastToolUse: "Bash: git")
        #expect(gitBare.isGithubTool == true)

        let ghBare = Agent.fixture(lastToolUse: "Bash: gh")
        #expect(ghBare.isGithubTool == true)

        // Non-git bash commands
        let swiftTest = Agent.fixture(lastToolUse: "Bash: swift test")
        #expect(swiftTest.isGithubTool == false)

        // MCP github tool
        let mcp = Agent.fixture(lastToolUse: "mcp__github__create_pr")
        #expect(mcp.isGithubTool == true)

        // Non-Bash tool
        let edit = Agent.fixture(lastToolUse: "Edit: Agent.swift")
        #expect(edit.isGithubTool == false)

        // Nil
        let none = Agent.fixture(lastToolUse: nil)
        #expect(none.isGithubTool == false)
    }

    @Test func isGithubPermissionWithNewFormat() {
        let gitPush = Agent.fixture(lastToolUse: "Bash: git push --force")
        #expect(gitPush.isGithubPermission == true)

        let ghPr = Agent.fixture(lastToolUse: "Bash: gh pr merge")
        #expect(ghPr.isGithubPermission == true)

        let npmInstall = Agent.fixture(lastToolUse: "Bash: npm install")
        #expect(npmInstall.isGithubPermission == false)
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

    // MARK: - effectiveStatus

    @Test("effectiveStatus returns parent status when no children")
    func effectiveStatusNoChildren() {
        let parent = Agent.fixture(status: .working)
        #expect(Agent.effectiveStatus(of: parent, children: []) == .working)
    }

    @Test("effectiveStatus returns child permission when parent is working")
    func effectiveStatusChildPermission() {
        let parent = Agent.fixture(status: .working)
        let childA = Agent.fixture(sessionId: "child-a", status: .permission)
        let childB = Agent.fixture(sessionId: "child-b", status: .working)
        #expect(Agent.effectiveStatus(of: parent, children: [childA, childB]) == .permission)
    }

    @Test("effectiveStatus returns child waiting when parent is working")
    func effectiveStatusChildWaiting() {
        let parent = Agent.fixture(status: .working)
        let child = Agent.fixture(sessionId: "child", status: .waiting)
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .waiting)
    }

    @Test("effectiveStatus prefers permission over waiting among children")
    func effectiveStatusPermissionBeatsWaiting() {
        let parent = Agent.fixture(status: .working)
        let childA = Agent.fixture(sessionId: "child-a", status: .waiting)
        let childB = Agent.fixture(sessionId: "child-b", status: .permission)
        #expect(Agent.effectiveStatus(of: parent, children: [childA, childB]) == .permission)
    }

    @Test("effectiveStatus keeps parent status when more urgent than children")
    func effectiveStatusParentMoreUrgent() {
        let parent = Agent.fixture(status: .permission)
        let child = Agent.fixture(sessionId: "child", status: .working)
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .permission)
    }

    @Test("effectiveStatus returns delegating when parent is done but children are working")
    func effectiveStatusDelegating() {
        let parent = Agent.fixture(status: .waiting, waitReason: "done")
        let child = Agent.fixture(sessionId: "child", status: .working)
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .delegating)
    }

    @Test("effectiveStatus returns delegating when parent is done and child is starting")
    func effectiveStatusDelegatingChildStarting() {
        let parent = Agent.fixture(status: .waiting, waitReason: "done")
        let child = Agent.fixture(sessionId: "child", status: .starting)
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .delegating)
    }

    @Test("effectiveStatus does NOT return delegating when parent is waiting with question")
    func effectiveStatusNotDelegatingOnQuestion() {
        let parent = Agent.fixture(status: .waiting, waitReason: "question")
        let child = Agent.fixture(sessionId: "child", status: .working)
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .waiting)
    }

    @Test("effectiveStatus promotes child permission over delegating")
    func effectiveStatusPermissionOverridesDelegating() {
        let parent = Agent.fixture(status: .waiting, waitReason: "done")
        let childA = Agent.fixture(sessionId: "child-a", status: .working)
        let childB = Agent.fixture(sessionId: "child-b", status: .permission)
        #expect(Agent.effectiveStatus(of: parent, children: [childA, childB]) == .permission)
    }

    @Test("effectiveStatus returns waiting-done when parent is done and all children are done")
    func effectiveStatusNotDelegatingAllChildrenDone() {
        let parent = Agent.fixture(status: .waiting, waitReason: "done")
        let child = Agent.fixture(sessionId: "child", status: .waiting, waitReason: "done")
        #expect(Agent.effectiveStatus(of: parent, children: [child]) == .waiting)
    }

    @Test("mostUrgentChild returns nil when no children")
    func mostUrgentChildNone() {
        let parent = Agent.fixture()
        #expect(Agent.mostUrgentChild(of: parent, children: []) == nil)
    }

    @Test("mostUrgentChild returns permission child over working child")
    func mostUrgentChildPermission() {
        let parent = Agent.fixture()
        let childA = Agent.fixture(sessionId: "child-a", status: .working, lastToolUse: "Bash: ls")
        let childB = Agent.fixture(sessionId: "child-b", status: .permission, lastToolUse: "Bash: rm -rf /")
        let urgent = Agent.mostUrgentChild(of: parent, children: [childA, childB])
        #expect(urgent?.sessionId == "child-b")
        #expect(urgent?.isBashPermission == true)
    }
}
