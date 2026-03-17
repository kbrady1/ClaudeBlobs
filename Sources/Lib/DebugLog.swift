import Foundation

final class DebugLog {
    static let shared = DebugLog()
    private let logPath = "/tmp/claude-agent-hud-debug.log"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "debugMode") }
        set { UserDefaults.standard.set(newValue, forKey: "debugMode") }
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
}
