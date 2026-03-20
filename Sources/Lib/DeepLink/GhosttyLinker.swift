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

    /// Ghostty tabs don't expose a TTY property, but their focused terminal
    /// has a `working directory` we can match against the agent's cwd.
    static func selectTab(cwd: String, title: String? = nil) async -> Bool {
        // Sanitize cwd: only allow simple path characters to prevent injection
        guard cwd.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else {
            DebugLog.shared.log("GhosttyLinker: cwd contains unsafe characters: \(cwd)")
            return false
        }

        let escapedCwd = scriptLiteral(cwd)
        let escapedTitle = title.map(scriptLiteral)

        if let escapedTitle, !escapedTitle.isEmpty {
            let titledSource = """
            tell application id "com.mitchellh.ghostty"
                repeat with w in windows
                    repeat with t in tabs of w
                        if working directory of focused terminal of t is "\(escapedCwd)" and name of focused terminal of t contains "\(escapedTitle)" then
                            select tab t
                            activate window w
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
            DebugLog.shared.log("GhosttyLinker: selecting tab for cwd \(cwd) title \(title ?? "")")
            if await AppleScriptRunner.run(titledSource) {
                return true
            }
        }

        let source = """
        tell application id "com.mitchellh.ghostty"
            repeat with w in windows
                repeat with t in tabs of w
                    if working directory of focused terminal of t is "\(escapedCwd)" then
                        select tab t
                        activate window w
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        DebugLog.shared.log("GhosttyLinker: selecting tab for cwd \(cwd)")
        return await AppleScriptRunner.run(source)
    }
}
