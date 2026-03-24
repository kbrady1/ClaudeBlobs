// Tests/CommandExecutorTests.swift
import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("CommandExecutor")
struct CommandExecutorTests {

    @Test func rejectsNonCmuxAgent() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .permission)
        let result = try await CommandExecutor.execute(command: .approve, agent: agent, text: nil)
        #expect(result.success == false)
        #expect(result.error?.contains("cmux") == true)
    }

    @Test func rejectsApproveOnWorkingAgent() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .working, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .approve, agent: agent, text: nil)
        #expect(result.success == false)
    }

    @Test func rejectsRespondOnWorkingAgent() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .working, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .respond, agent: agent, text: "hello")
        #expect(result.success == false)
        #expect(result.error?.contains("working") == true)
    }

    @Test func allowsRespondOnWaitingAgent() async throws {
        // This will fail at the cmux call (no real cmux), but should get past validation
        let agent = Agent.fixture(sessionId: "s1", status: .waiting, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .respond, agent: agent, text: "yes")
        // Will fail because cmux isn't running, but the error should be about cmux, not validation
        #expect(result.success == false)
        #expect(result.error?.contains("cmux") == true || result.error?.contains("No such file") == true)
    }

    @Test func selectOptionRequiresIndex() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .permission, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .selectOption, agent: agent, text: nil, optionIndex: nil)
        #expect(result.success == false)
        #expect(result.error?.contains("index") == true)
    }

    @Test func respondWithoutTextFails() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .waiting, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .respond, agent: agent, text: nil)
        #expect(result.success == false)
        #expect(result.error?.contains("text") == true)
    }

    @Test func parsePermissionOptionsFromScreen() {
        let screen = """
        ⏺ Update(file.swift)
        ─────────────────────────
        Do you want to make this edit?
        ❯ 1. Yes, and tell Claude what to do next
          2. Yes, allow all edits during this session (shift+tab)
          3. No

         Esc to cancel
        """
        let options = CommandExecutor.parsePermissionOptions(from: screen)
        #expect(options.count == 3)
        #expect(options[0].hasPrefix("Yes, and tell"))
        #expect(options[1].contains("allow all"))
        #expect(options[2] == "No")
    }

    @Test func parsePermissionOptionsIgnoresConversationNumberedLists() {
        let screen = """
        Here are the available options from the config:
        1. Enable notifications
        2. Disable logging
        3. Reset defaults
        4. Update credentials
        5. Clear cache
        6. Run diagnostics
        7. Export data
        8. Import settings
        9. Toggle dark mode

        ? Allow Bash: npm install
        ❯ 1. Yes, and tell Claude what to do next
          2. Yes, allow all Bash commands during this session
          3. No
        """
        let options = CommandExecutor.parsePermissionOptions(from: screen)
        #expect(options.count == 3)
        #expect(options[0].hasPrefix("Yes, and tell"))
        #expect(options[2] == "No")
    }

    @Test func cursorIndexIgnoresConversationNumberedLists() {
        let screen = """
        1. First item in conversation
        2. Second item in conversation

        ? Allow Edit: file.swift
          1. Yes, and tell Claude what to do next
        ❯ 2. Yes, allow all edits
          3. No
        """
        #expect(CommandExecutor.currentCursorIndex(from: screen) == 1)
    }

    @Test func respondRejectsOversizeText() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .waiting, cmuxSurface: "surface:1")
        let longText = String(repeating: "x", count: CommandExecutor.maxRespondTextLength + 1)
        let result = try await CommandExecutor.execute(command: .respond, agent: agent, text: longText)
        #expect(result.success == false)
        #expect(result.error?.contains("maximum length") == true)
    }

    @Test func cursorIndexDetection() {
        let screen1 = """
        ❯ 1. First option
          2. Second option
          3. Third option
        """
        #expect(CommandExecutor.currentCursorIndex(from: screen1) == 0)

        let screen2 = """
          1. First option
        ❯ 2. Second option
          3. Third option
        """
        #expect(CommandExecutor.currentCursorIndex(from: screen2) == 1)
    }
}
