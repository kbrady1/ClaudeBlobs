import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("DeepLinker")
struct DeepLinkerTests {
    @Test func routesToCmuxForCmuxSession() {
        let agent = Agent.fixture(cmuxWorkspace: "ws:abc", cmuxSurface: "surface:def")
        #expect(DeepLinker.linkType(for: agent) == .cmux)
    }

    @Test func routesToSupersetForSupersetSession() {
        let agent = Agent.fixture(
            cwd: "/Users/test/.superset/worktrees/proj/x",
            supersetWorkspace: "7d22d2e0-dd86-4adc-a397-f641ca6c3a92",
            supersetTerminal: "term-1-abc"
        )
        #expect(DeepLinker.linkType(for: agent) == .superset)
    }

    @Test func cmuxBeatsSupersetWhenBothPresent() {
        let agent = Agent.fixture(
            cmuxWorkspace: "ws:abc",
            cmuxSurface: "surface:def",
            supersetWorkspace: "ws-super"
        )
        #expect(DeepLinker.linkType(for: agent) == .cmux)
    }

    @Test func routesToTerminalForPlainCLI() {
        let agent = Agent.fixture(cwd: "/Users/test/code", cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(DeepLinker.linkType(for: agent) == .terminal)
    }

    @Test func routesToDesktopWhenNoCwd() {
        let agent = Agent.fixture(cwd: nil, cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(DeepLinker.linkType(for: agent) == .desktop)
    }

    @Test func routesOpenCodeToTerminalWithoutCwd() {
        let agent = Agent.fixture(provider: .openCode, cwd: nil, cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(DeepLinker.linkType(for: agent) == .terminal)
    }
}
