// Tests/CommandExecutorTests.swift
import Testing
@testable import ClaudeBlobsLib

@Suite("CommandExecutor")
struct CommandExecutorTests {

    @Test func approveBuildsCorrectCommands() {
        let cmds = CommandExecutor.buildCommands(
            command: .approve,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: nil
        )
        #expect(cmds.count == 2)
        #expect(cmds[0].contains("send-key"))
        #expect(cmds[0].contains("--surface"))
        #expect(cmds[0].contains("surface:1"))
        #expect(cmds[0].contains("y"))
        #expect(cmds[1].contains("Enter"))
    }

    @Test func denyBuildsEscapeCommand() {
        let cmds = CommandExecutor.buildCommands(
            command: .deny,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: nil
        )
        #expect(cmds.count == 1)
        #expect(cmds[0].contains("Escape"))
    }

    @Test func respondBuildsTextThenEnter() {
        let cmds = CommandExecutor.buildCommands(
            command: .respond,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: "yes, update the tests"
        )
        #expect(cmds.count == 2)
        #expect(cmds[0].contains("send"))
        #expect(cmds[0].contains("yes, update the tests"))
        #expect(cmds[1].contains("send-key"))
        #expect(cmds[1].contains("Enter"))
    }

    @Test func interruptBuildsSigintCommand() {
        let cmds = CommandExecutor.buildCommands(
            command: .interrupt,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: nil
        )
        #expect(cmds.count == 1)
        #expect(cmds[0].contains("C-c"))
    }

    @Test func respondWithoutTextReturnsEmpty() {
        let cmds = CommandExecutor.buildCommands(
            command: .respond,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: nil
        )
        #expect(cmds.isEmpty)
    }

    @Test func textIsPassedAsDiscreteArgument() {
        let cmds = CommandExecutor.buildCommands(
            command: .respond,
            cmuxSurface: "surface:1",
            cmuxSocketPath: "/tmp/cmux.sock",
            text: "hello; rm -rf /"
        )
        let sendCmd = cmds[0]
        #expect(sendCmd.contains("hello; rm -rf /"))
        #expect(sendCmd.last == "hello; rm -rf /")
    }
}
