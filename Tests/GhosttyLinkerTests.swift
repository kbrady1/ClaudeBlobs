import Testing
@testable import ClaudeBlobsLib

@Suite("GhosttyLinker")
struct GhosttyLinkerTests {

    // MARK: - looksLikeClaudeCodeTitle

    // Titles observed live: idle "Claude Code" panes and busy panes mid-task
    // both lead with a non-ASCII status glyph; only the idle one still
    // contains the literal substring "Claude Code".
    @Test func idleClaudeCodeTitleIsRecognized() {
        #expect(GhosttyLinker.looksLikeClaudeCodeTitle("✳ Claude Code"))
        #expect(GhosttyLinker.looksLikeClaudeCodeTitle("⠐ Claude Code"))
    }

    @Test func busyTaskTitleWithoutClaudeCodeSubstringIsStillRecognized() {
        #expect(GhosttyLinker.looksLikeClaudeCodeTitle("✳ Review Apple Ads integration setup"))
        #expect(GhosttyLinker.looksLikeClaudeCodeTitle("⠂ darwin-bulk-scan-renderer"))
    }

    @Test func plainShellTitlesAreNotRecognized() {
        #expect(!GhosttyLinker.looksLikeClaudeCodeTitle("kentbrady@Kents-MacBook-Pro-2: ~/SourceCode/rails-api"))
        #expect(!GhosttyLinker.looksLikeClaudeCodeTitle("~/SourceCode/react-native"))
        #expect(!GhosttyLinker.looksLikeClaudeCodeTitle("~/SourceCode/DiskBloom"))
    }

    @Test func emptyTitleIsNotRecognized() {
        #expect(!GhosttyLinker.looksLikeClaudeCodeTitle(""))
    }

    // MARK: - pickTerminal

    @Test func prefersClaudeCodePaneOverPlainShellSharingCwd() {
        let cwd = "/Users/kentbrady/SourceCode/react-native"
        let terminals = [
            GhosttyLinker.Terminal(id: "1", name: "~/SourceCode/react-native", cwd: cwd),
            GhosttyLinker.Terminal(id: "2", name: "✳ Review Apple Ads integration setup", cwd: cwd),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: cwd, title: nil)
        #expect(picked?.id == "2")
    }

    @Test func regressionBusyTaskTitleStillWinsOverPlainShell() {
        // The bug this guards against: a prior fix matched the literal
        // substring "Claude Code", which only matches while idle. Once the
        // agent starts a task the title changes to the task description and
        // that match silently breaks, falling back to an arbitrary pick that
        // could land on a plain shell instead.
        let cwd = "/Users/kentbrady/SourceCode/react-native"
        let terminals = [
            GhosttyLinker.Terminal(id: "shell", name: "~/SourceCode/react-native", cwd: cwd),
            GhosttyLinker.Terminal(id: "busy", name: "⠂ darwin-bulk-scan-renderer", cwd: cwd),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: cwd, title: nil)
        #expect(picked?.id == "busy")
    }

    @Test func exactTitleMatchWinsOverGlyphHeuristic() {
        let cwd = "/tmp/project"
        let terminals = [
            GhosttyLinker.Terminal(id: "other", name: "✳ Some other task", cwd: cwd),
            GhosttyLinker.Terminal(id: "target", name: "✳ Fix the login bug", cwd: cwd),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: cwd, title: "Fix the login bug")
        #expect(picked?.id == "target")
    }

    @Test func titleMatchIsCaseInsensitive() {
        let cwd = "/tmp/project"
        let terminals = [
            GhosttyLinker.Terminal(id: "target", name: "✳ FIX THE LOGIN BUG", cwd: cwd),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: cwd, title: "fix the login bug")
        #expect(picked?.id == "target")
    }

    @Test func cwdMatchIsCaseInsensitive() {
        let terminals = [
            GhosttyLinker.Terminal(id: "target", name: "✳ Claude Code", cwd: "/Users/kentbrady/SourceCode/App"),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: "/users/kentbrady/sourcecode/app", title: nil)
        #expect(picked?.id == "target")
    }

    @Test func fallsBackToFirstMatchWhenNoClaudeCodePaneFound() {
        let cwd = "/tmp/project"
        let terminals = [
            GhosttyLinker.Terminal(id: "shell1", name: "~/project", cwd: cwd),
            GhosttyLinker.Terminal(id: "shell2", name: "user@host: ~/project", cwd: cwd),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: cwd, title: nil)
        #expect(picked?.id == "shell1")
    }

    @Test func returnsNilWhenNoTerminalMatchesCwd() {
        let terminals = [
            GhosttyLinker.Terminal(id: "1", name: "✳ Claude Code", cwd: "/somewhere/else"),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: "/tmp/project", title: nil)
        #expect(picked == nil)
    }

    @Test func ignoresNonMatchingCwdsEvenWithClaudeCodeTitle() {
        let terminals = [
            GhosttyLinker.Terminal(id: "wrong", name: "✳ Claude Code", cwd: "/other/project"),
            GhosttyLinker.Terminal(id: "right", name: "~/project", cwd: "/tmp/project"),
        ]
        let picked = GhosttyLinker.pickTerminal(terminals, cwd: "/tmp/project", title: nil)
        #expect(picked?.id == "right")
    }
}
