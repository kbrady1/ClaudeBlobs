import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("TerminalLinker")
struct TerminalLinkerTests {

    // MARK: - Agent TTY decoding

    @Test func agentWithTTYDecodes() throws {
        let json = """
        {
            "sessionId": "s1",
            "pid": 100,
            "cwd": "/tmp",
            "tty": "/dev/ttys003",
            "status": "working",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.tty == "/dev/ttys003")
    }

    @Test func agentWithoutTTYDecodesAsNil() throws {
        let json = """
        {
            "sessionId": "s1",
            "pid": 100,
            "status": "working",
            "updatedAt": 1000
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        #expect(agent.tty == nil)
    }

    @Test func agentFixtureIncludesTTY() {
        let agent = Agent.fixture(tty: "/dev/ttys005")
        #expect(agent.tty == "/dev/ttys005")
    }

    // MARK: - TTY path validation

    @Test func validTTYPaths() {
        #expect(AppleScriptRunner.isValidTTYPath("/dev/ttys003"))
        #expect(AppleScriptRunner.isValidTTYPath("/dev/ttys0"))
        #expect(AppleScriptRunner.isValidTTYPath("/dev/ttys1234"))
    }

    @Test func invalidTTYPaths() {
        #expect(!AppleScriptRunner.isValidTTYPath(""))
        #expect(!AppleScriptRunner.isValidTTYPath("/dev/tty"))
        #expect(!AppleScriptRunner.isValidTTYPath("/dev/ttys"))
        #expect(!AppleScriptRunner.isValidTTYPath("/dev/ttys003; rm -rf /"))
        #expect(!AppleScriptRunner.isValidTTYPath("foo\"; do evil; \""))
        #expect(!AppleScriptRunner.isValidTTYPath("/dev/ttys12345"))
        #expect(!AppleScriptRunner.isValidTTYPath("/tmp/ttys003"))
    }

    // MARK: - ProcessTree TTY resolution

    @Test func controllingTTYReturnsPlausiblePath() {
        let pid = ProcessInfo.processInfo.processIdentifier
        // The test process should have a controlling TTY (or nil in CI)
        if let tty = ProcessTree.controllingTTY(of: pid) {
            #expect(AppleScriptRunner.isValidTTYPath(tty))
        }
    }

    @Test func resolveTTYWalksAncestors() {
        let pid = ProcessInfo.processInfo.processIdentifier
        // resolveTTY should return the same or parent's TTY
        if let tty = ProcessTree.resolveTTY(of: pid) {
            #expect(AppleScriptRunner.isValidTTYPath(tty))
        }
    }
}
