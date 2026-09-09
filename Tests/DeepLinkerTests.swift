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

    @Test func focusesExistingDesktopSession() {
        let agent = Agent.fixture(sessionId: "122c7a92-ff70-4790-bfe0-b097e5c41af7")
        let route = DesktopLinker.route(
            for: agent,
            localSessionId: "local_115a68e0-6cde-4823-9640-d17816cd0692"
        )
        #expect(route == .focus(localSessionId: "local_115a68e0-6cde-4823-9640-d17816cd0692"))
        #expect(
            route?.url?.absoluteString
                == "claude://claude.ai/epitaxy/local_115a68e0-6cde-4823-9640-d17816cd0692"
        )
    }

    @Test func importsTranscriptWhenDesktopHasNoSession() {
        let agent = Agent.fixture(sessionId: "0859bda4-73a8-4662-b9cc-c9edecc6a776")
        let route = DesktopLinker.route(for: agent, localSessionId: nil)
        #expect(route == .importTranscript(cliSessionId: "0859bda4-73a8-4662-b9cc-c9edecc6a776"))
        #expect(
            route?.url?.absoluteString
                == "claude://resume?session=0859bda4-73a8-4662-b9cc-c9edecc6a776"
        )
    }

    @Test func noRouteForNonUUIDSessionIdWithoutDesktopSession() {
        let agent = Agent.fixture(sessionId: "not-a-uuid")
        #expect(DesktopLinker.route(for: agent, localSessionId: nil) == nil)
    }

    @Test func noRouteForOpenCode() {
        let agent = Agent.fixture(
            provider: .openCode,
            sessionId: "0859bda4-73a8-4662-b9cc-c9edecc6a776"
        )
        #expect(DesktopLinker.route(for: agent, localSessionId: nil) == nil)
    }
}
