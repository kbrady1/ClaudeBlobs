import Foundation

final class DebugLog {
    static let shared = DebugLog()
    private let logDir: String = NSHomeDirectory() + "/Library/Logs/ClaudeBlobs"
    private let logPath: String = {
        let dir = NSHomeDirectory() + "/Library/Logs/ClaudeBlobs"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/debug.log"
    }()
    let hookLogDir: String = NSHomeDirectory() + "/Library/Logs/ClaudeBlobs/hooks"
    private let debugFlagPath: String = NSHomeDirectory() + "/Library/Logs/ClaudeBlobs/.debug-enabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "debugMode") }
        set {
            UserDefaults.standard.set(newValue, forKey: "debugMode")
            syncDebugFlag(newValue)
        }
    }

    /// Ensure the flag file matches the current UserDefaults state (call on launch).
    func syncDebugFlagOnLaunch() {
        syncDebugFlag(UserDefaults.standard.bool(forKey: "debugMode"))
    }

    private func syncDebugFlag(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: debugFlagPath) {
                fm.createFile(atPath: debugFlagPath, contents: nil)
            }
        } else {
            try? fm.removeItem(atPath: debugFlagPath)
        }
    }

    func log(_ message: String) {
        guard isEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(atPath: logPath)
    }

    func clearHookLogs() {
        try? FileManager.default.removeItem(atPath: hookLogDir)
    }

    /// List session IDs that have hook log files.
    func hookLogSessionIds() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: hookLogDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".log") }
            .map { String($0.dropLast(4)) }
    }

    func hookLogPath(for sessionId: String) -> String {
        hookLogDir + "/\(sessionId).log"
    }
}
