import Foundation

enum ITermLinker {
    static let bundleId = "com.googlecode.iterm2"

    static func selectTab(tty: String) async -> Bool {
        guard AppleScriptRunner.isValidTTYPath(tty) else {
            DebugLog.shared.log("ITermLinker: invalid TTY path: \(tty)")
            return false
        }

        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        DebugLog.shared.log("ITermLinker: selecting tab for tty \(tty)")
        return await AppleScriptRunner.run(source)
    }
}
