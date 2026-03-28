import Testing
import Foundation
@testable import ClaudeBlobsLib

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
        #expect(AgentStatus.delegating.visibleWhenCollapsed == true)
        #expect(AgentStatus.working.visibleWhenCollapsed == false)
        #expect(AgentStatus.compacting.visibleWhenCollapsed == false)
    }

    @Test func compactingStatus() {
        let status = AgentStatus.compacting
        #expect(status.displayName == "Compacting")
        #expect(status.visibleWhenCollapsed == false)
    }

    @Test func delegatingStatus() {
        let status = AgentStatus.delegating
        #expect(status.displayName == "Delegating")
        #expect(status.visibleWhenCollapsed == true)
        #expect(status.sortPriority == 2)
    }

    @Test func delegatingSortsBetweenWaitingAndWorking() {
        #expect(AgentStatus.waiting.sortPriority < AgentStatus.delegating.sortPriority)
        #expect(AgentStatus.delegating.sortPriority < AgentStatus.working.sortPriority)
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

        // Permission no longer uses "Wants to run:" prefix
        let permission = Agent.fixture(
            status: .permission,
            lastMessage: nil,
            lastToolUse: "rm -rf /tmp"
        )
        #expect(permission.speechBubbleText == "rm -rf /tmp")

        let permissionNoTool = Agent.fixture(
            status: .permission,
            lastMessage: nil,
            lastToolUse: nil
        )
        #expect(permissionNoTool.speechBubbleText == "")

        let starting = Agent.fixture(status: .starting)
        #expect(starting.speechBubbleText == "Starting up...")
    }

    // MARK: - cleanMessage

    @Test func cleanMessage_stripsMarkdown() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "## Session `17f26` Summary"
        )
        #expect(agent.cleanMessage == "Session 17f26 Summary")
    }

    @Test func cleanMessage_stripsFiller() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "Good, I now have a thorough understanding of the codebase",
            rawLastMessage: "Good, I now have a thorough understanding of the codebase. The hooks use shell scripts that write JSON status files."
        )
        // Should skip filler and pull from rawLastMessage since cleaned text is short
        #expect(!agent.cleanMessage.hasPrefix("Good"))
        #expect(agent.cleanMessage.count > 15)
    }

    @Test func cleanMessage_preservesUsefulContent() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "Build passes with --rerun-tasks"
        )
        #expect(agent.cleanMessage == "Build passes with --rerun-tasks")
    }

    @Test func cleanMessage_emptyWhenNil() {
        let agent = Agent.fixture(status: .waiting, lastMessage: nil)
        #expect(agent.cleanMessage == "")
    }

    @Test func cleanMessage_fallsBackToRaw() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "Good clarification",
            rawLastMessage: "Good clarification. CoWork hooks already fire, deep-linking only activates Desktop generically."
        )
        // "Good clarification" cleaned → "clarification" (short), so should fall back to raw
        let result = agent.cleanMessage
        #expect(result.contains("CoWork") || result.contains("hooks") || result.contains("deep-link"))
    }

    // MARK: - cleanToolUse

    @Test func cleanToolUse_bashStripsPathsAndRedirects() {
        let agent = Agent.fixture(
            status: .working,
            lastToolUse: "Bash: cd /Users/kentbrady/SourceCode/android/ReactNative && npm run build:android 2>&1"
        )
        #expect(agent.cleanToolUse == "npm run build:android")
    }

    @Test func cleanToolUse_internalToolsFriendlyNames() {
        let taskUpdate = Agent.fixture(status: .working, lastToolUse: "TaskUpdate: {\"taskId\":\"2\",\"status\":\"in_progress\"}")
        #expect(taskUpdate.cleanToolUse == "Updating tasks")

        let exitPlan = Agent.fixture(status: .working, lastToolUse: "ExitPlanMode: {\"allowedPrompts\":[]}")
        #expect(exitPlan.cleanToolUse == "Submitting plan")

        let skill = Agent.fixture(status: .working, lastToolUse: "Skill: superpowers:brainstorming")
        #expect(skill.cleanToolUse == "Loading skill")

        let toolSearch = Agent.fixture(status: .working, lastToolUse: "ToolSearch: {\"query\":\"select:ExitPlanMode\"}")
        #expect(toolSearch.cleanToolUse == "Looking up tools")
    }

    @Test func cleanToolUse_fileToolsGerund() {
        let read = Agent.fixture(status: .working, lastToolUse: "Read: AppCoordinatorImpl.kt")
        #expect(read.cleanToolUse == "Reading AppCoordinatorImpl.kt")

        let edit = Agent.fixture(status: .working, lastToolUse: "Edit: FaqScreen.tsx")
        #expect(edit.cleanToolUse == "Editing FaqScreen.tsx")

        let write = Agent.fixture(status: .working, lastToolUse: "Write: mobile-ui.html")
        #expect(write.cleanToolUse == "Writing mobile-ui.html")
    }

    @Test func cleanToolUse_searchTools() {
        let grep = Agent.fixture(status: .working, lastToolUse: "Grep: headerShown|NativeStackNavigationOptions|screenOptions")
        #expect(grep.cleanToolUse == "Search: headerShown")

        let web = Agent.fixture(status: .working, lastToolUse: "WebSearch: claude desktop API")
        #expect(web.cleanToolUse == "Web: claude desktop API")
    }

    @Test func cleanToolUse_mcpTools() {
        let mcp = Agent.fixture(status: .working, lastToolUse: "mcp__github__create_pr")
        #expect(mcp.cleanToolUse == "github: create_pr")
    }

    // MARK: - permissionToolUse

    @Test func permissionToolUse_bashImperative() {
        let agent = Agent.fixture(
            status: .permission,
            lastToolUse: "Bash: ls ~/.claude/hook-logs/ | head -30"
        )
        #expect(agent.permissionToolUse.hasPrefix("Run: "))
        #expect(agent.permissionToolUse.contains("ls"))
    }

    @Test func permissionToolUse_fileToolsImperative() {
        let read = Agent.fixture(status: .permission, lastToolUse: "Read: AppCoordinatorImpl.kt")
        #expect(read.permissionToolUse == "Read AppCoordinatorImpl.kt")

        let edit = Agent.fixture(status: .permission, lastToolUse: "Edit: FaqScreen.tsx")
        #expect(edit.permissionToolUse == "Edit FaqScreen.tsx")
    }

    @Test func permissionToolUse_exitPlanMode() {
        let agent = Agent.fixture(status: .permission, lastToolUse: "ExitPlanMode: {\"allowedPrompts\":[]}")
        #expect(agent.permissionToolUse == "Approve plan")
    }

    @Test func permissionToolUse_webSearch() {
        let agent = Agent.fixture(status: .permission, lastToolUse: "WebSearch: claude desktop API")
        #expect(agent.permissionToolUse == "Web: claude desktop API")
    }

    @Test func permissionToolUse_askUserQuestion() {
        let agent = Agent.fixture(
            status: .permission,
            lastToolUse: "AskUserQuestion: {\"questions\":[{\"question\":\"For the expanded HUD subagent display, which approach do you prefer?\"}]}"
        )
        #expect(agent.permissionToolUse.hasPrefix("Ask: "))
        #expect(agent.permissionToolUse.contains("expanded HUD"))
    }

    // MARK: - notificationMessage

    @Test func notificationMessage_usesRawForRicherContent() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "Build passes with --rerun-tasks",
            rawLastMessage: "Build passes with --rerun-tasks. The previous failure was a stale Gradle incremental compilation cache. The errors are gone now with a clean recompile."
        )
        let msg = agent.notificationMessage
        #expect(msg.contains("stale Gradle"))
        #expect(msg.count > 50)
    }

    @Test func notificationMessage_fallsBackToCleanMessage() {
        let agent = Agent.fixture(
            status: .waiting,
            lastMessage: "Tests are passing",
            rawLastMessage: nil
        )
        #expect(agent.notificationMessage == "Tests are passing")
    }

    // MARK: - Bash cleaning

    @Test func cleanBashCommand_stripsAbsolutePaths() {
        let result = Agent.cleanBashCommand("cd /Users/kentbrady/SourceCode/android/ReactNative && npm run build:android 2>&1")
        #expect(result == "npm run build:android")
    }

    @Test func cleanBashCommand_stripsTrailingPipes() {
        let result = Agent.cleanBashCommand("./gradlew :app:compileDebugKotlin --rerun-tasks 2>&1 | grep \"BUILD\" | tail -5")
        #expect(result == "./gradlew :app:compileDebugKotlin --rerun-tasks")
    }

    @Test func cleanBashCommand_simplePath() {
        let result = Agent.cleanBashCommand("ls /Users/kentbrady/.claude/hook-logs/ | head -30")
        #expect(result == "ls ~/.claude/hook-logs/")
    }
}
