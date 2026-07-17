import Foundation

enum GhosttyLinker {
    static let bundleId = "com.mitchellh.ghostty"

    /// A Ghostty terminal surface as reported by `list terminals`.
    struct Terminal: Equatable {
        let id: String
        let name: String
        let cwd: String
    }

    private static func scriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    // Field/record separators for the enumeration script's output. Control
    // characters can't appear in a Ghostty title or a filesystem path.
    private static let fieldSeparator = "\u{1F}"
    private static let recordSeparator = "\u{1E}"

    /// True if a terminal's title looks like it's being driven by Claude Code
    /// rather than a plain shell prompt. Claude Code always prefixes its title
    /// with a status glyph (a spinner frame, "✳", etc.) followed by either
    /// "Claude Code" (idle) or the current task description (busy) — the task
    /// text changes as the agent works, so matching a literal substring like
    /// "Claude Code" only holds up while idle and breaks the moment the agent
    /// starts a task. A plain shell's title is always a plain-ASCII path or
    /// "user@host: path", so checking that the title's first character is
    /// non-ASCII identifies a Claude Code pane regardless of its current
    /// status text.
    static func looksLikeClaudeCodeTitle(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        return !first.isASCII
    }

    /// Picks which terminal to focus for an agent's cwd (and optional session
    /// title), out of every terminal Ghostty currently has open. Pure and
    /// exposed for testing, since the AppleScript surface it's normally fed
    /// from can't be unit tested directly. Comparisons are case-insensitive
    /// to match AppleScript's default `is`/`contains` text comparison
    /// semantics, which this replaces.
    static func pickTerminal(_ terminals: [Terminal], cwd: String, title: String?) -> Terminal? {
        let matches = terminals.filter { $0.cwd.caseInsensitiveCompare(cwd) == .orderedSame }
        if let title, !title.isEmpty,
           let exact = matches.first(where: { $0.name.localizedCaseInsensitiveContains(title) }) {
            return exact
        }
        if let claudeMatch = matches.first(where: { looksLikeClaudeCodeTitle($0.name) }) {
            return claudeMatch
        }
        return matches.first
    }

    private static func parseTerminals(_ raw: String) -> [Terminal] {
        raw.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count == 3, !fields[0].isEmpty else { return nil }
            return Terminal(id: fields[0], name: fields[1], cwd: fields[2])
        }
    }

    /// Ghostty terminals (individual panes/splits) don't expose a TTY or PID
    /// property, but each one has a `working directory` we can match against
    /// the agent's cwd. Enumerates every terminal in every window — not just
    /// each tab's `focused terminal` — since a tab can have multiple panes
    /// sharing the same cwd (e.g. a shell split next to the Claude Code
    /// pane), and the pane that happens to have OS-level focus may not be
    /// the right one. `focus <terminal>` selects its tab, brings the window
    /// forward, and switches pane focus to it in one call.
    static func selectTab(cwd: String, title: String? = nil) async -> Bool {
        // Sanitize cwd: only allow simple path characters to prevent injection
        guard cwd.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else {
            DebugLog.shared.log("GhosttyLinker: cwd contains unsafe characters: \(cwd)")
            return false
        }

        let listSource = """
        tell application id "com.mitchellh.ghostty"
            set output to {}
            repeat with w in windows
                repeat with term in terminals of w
                    set end of output to (id of term) & "\(fieldSeparator)" & (name of term) & "\(fieldSeparator)" & (working directory of term)
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\(recordSeparator)"
            return output as text
        end tell
        """
        guard let raw = await AppleScriptRunner.runReturningString(listSource) else {
            DebugLog.shared.log("GhosttyLinker: failed to enumerate terminals")
            return false
        }

        let terminals = parseTerminals(raw)
        guard let picked = pickTerminal(terminals, cwd: cwd, title: title) else {
            DebugLog.shared.log("GhosttyLinker: no terminal matches cwd \(cwd)")
            return false
        }

        DebugLog.shared.log("GhosttyLinker: focusing terminal id \(picked.id) name \(picked.name) for cwd \(cwd)")
        // `focus term` switches which pane has keyboard focus within its window,
        // but a prior fix that switched from the original `select tab` + `activate
        // window` pair to `focus` alone found that `focus` doesn't reliably raise
        // the window itself when triggered by an Apple Event from a background
        // app (as opposed to an interactive shell) — the pane focus changed but
        // the window silently stayed behind whatever else was frontmost. Calling
        // `activate window` explicitly restores the previously-reliable
        // window-raising behavior.
        let focusSource = """
        tell application id "com.mitchellh.ghostty"
            repeat with w in windows
                repeat with term in terminals of w
                    if id of term is "\(scriptLiteral(picked.id))" then
                        focus term
                        activate window w
                        return
                    end if
                end repeat
            end repeat
            error "terminal no longer exists"
        end tell
        """
        return await AppleScriptRunner.run(focusSource)
    }
}
