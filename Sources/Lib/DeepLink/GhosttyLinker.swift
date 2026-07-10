import Foundation

enum GhosttyLinker {
    static let bundleId = "com.mitchellh.ghostty"

    private static func scriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Ghostty terminals (individual panes/splits) don't expose a TTY property,
    /// but each one has a `working directory` we can match against the agent's
    /// cwd. Match against every terminal in the window — not just each tab's
    /// `focused terminal` — since a tab can have multiple panes sharing the
    /// same cwd (e.g. a shell split next to the Claude Code pane), and the
    /// pane that happens to have OS-level focus may not be the right one.
    /// `focus <terminal>` selects its tab, brings the window forward, and
    /// switches pane focus to it in one call.
    static func selectTab(cwd: String, title: String? = nil) async -> Bool {
        // Sanitize cwd: only allow simple path characters to prevent injection
        guard cwd.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else {
            DebugLog.shared.log("GhosttyLinker: cwd contains unsafe characters: \(cwd)")
            return false
        }

        let escapedCwd = scriptLiteral(cwd)
        let escapedTitle = title.map(scriptLiteral)

        // NSAppleScript reports success/failure solely from whether the script
        // raised a runtime error — a script that runs to completion without
        // finding a match still reports success. So each branch below raises
        // an explicit error on no-match, letting the caller's unhide/activate
        // fallback actually fire when nothing was found.
        if let escapedTitle, !escapedTitle.isEmpty {
            let titledSource = """
            tell application id "com.mitchellh.ghostty"
                repeat with w in windows
                    repeat with term in terminals of w
                        if working directory of term is "\(escapedCwd)" and name of term contains "\(escapedTitle)" then
                            focus term
                            return
                        end if
                    end repeat
                end repeat
                error "no matching terminal"
            end tell
            """
            DebugLog.shared.log("GhosttyLinker: focusing terminal for cwd \(cwd) title \(title ?? "")")
            if await AppleScriptRunner.run(titledSource) {
                return true
            }
        }

        // Fallback: match by cwd alone. Multiple panes commonly share a cwd
        // (e.g. a plain shell split next to the Claude Code pane), so prefer
        // whichever one Claude Code itself titled — otherwise any cwd match
        // is a coin flip between them.
        let source = """
        tell application id "com.mitchellh.ghostty"
            set anyMatch to missing value
            repeat with w in windows
                repeat with term in terminals of w
                    if working directory of term is "\(escapedCwd)" then
                        if name of term contains "Claude Code" then
                            focus term
                            return
                        end if
                        if anyMatch is missing value then set anyMatch to term
                    end if
                end repeat
            end repeat
            if anyMatch is not missing value then
                focus anyMatch
            else
                error "no matching terminal"
            end if
        end tell
        """
        DebugLog.shared.log("GhosttyLinker: focusing terminal for cwd \(cwd)")
        return await AppleScriptRunner.run(source)
    }
}
