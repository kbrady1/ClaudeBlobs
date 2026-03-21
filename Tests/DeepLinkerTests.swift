import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("DeepLinker")
struct DeepLinkerTests {
    @Test func routesToCmuxForCmuxSession() {
        let agent = Agent.fixture(cmuxWorkspace: "ws:abc", cmuxSurface: "surface:def")
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
