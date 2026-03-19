import Foundation

enum GhosttyLinker {
    static let bundleId = "com.mitchellh.ghostty"

    /// Ghostty tabs don't expose a TTY property, but their focused terminal
    /// has a `working directory` we can match against the agent's cwd.
    static func selectTab(cwd: String) async -> Bool {
        // Sanitize cwd: only allow simple path characters to prevent injection
        guard cwd.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else {
            DebugLog.shared.log("GhosttyLinker: cwd contains unsafe characters: \(cwd)")
            return false
        }

        let source = """
        tell application id "com.mitchellh.ghostty"
            repeat with w in windows
                repeat with t in tabs of w
                    if working directory of focused terminal of t is "\(cwd)" then
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
