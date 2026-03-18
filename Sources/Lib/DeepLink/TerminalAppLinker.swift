import Foundation

enum TerminalAppLinker {
    static let bundleId = "com.apple.Terminal"

    static func selectTab(tty: String) async -> Bool {
        guard AppleScriptRunner.isValidTTYPath(tty) else {
            DebugLog.shared.log("TerminalAppLinker: invalid TTY path: \(tty)")
            return false
        }

        let source = """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        DebugLog.shared.log("TerminalAppLinker: selecting tab for tty \(tty)")
        return await AppleScriptRunner.run(source)
    }
}
