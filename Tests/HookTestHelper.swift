import Foundation

struct HookTestHelper {
    let tempHome: URL
    let statusDir: URL
    let hooksDir: String

    init() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-test-\(UUID().uuidString)")
        statusDir = tempHome.appendingPathComponent(".claude/agent-status")
        try FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)

        // Resolve hooksDir from project root
        let thisFile = URL(fileURLWithPath: #filePath)
        let projectRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        hooksDir = projectRoot.appendingPathComponent("Resources/hooks").path
    }

    struct HookResult {
        let exitCode: Int32
        let status: [String: Any]?
        let statusFileExists: Bool
    }

    /// Run a hook script, piping `input` JSON to stdin.
    /// If `existingStatus` is provided, it's written to the status file first.
    /// Returns the exit code and parsed status JSON (if the file exists after the run).
    @discardableResult
    func runHook(
        _ name: String,
        sessionId: String = "test-session",
        input: [String: Any]? = nil,
        environment: [String: String]? = nil,
        existingStatus: [String: Any]? = nil
    ) throws -> HookResult {
        var inputDict = input ?? [:]
        if inputDict["session_id"] == nil {
            inputDict["session_id"] = sessionId
        }

        let statusFile = statusDir.appendingPathComponent("\(sessionId).json")

        if let existing = existingStatus {
            let data = try JSONSerialization.data(withJSONObject: existing)
            try data.write(to: statusFile)
        }

        let inputData = try JSONSerialization.data(withJSONObject: inputDict)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["\(hooksDir)/\(name)"]

        var env: [String: String] = [
            "HOME": tempHome.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "PPID": "99999",
        ]
        if let extra = environment {
            env.merge(extra) { _, new in new }
        }
        process.environment = env

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        stdin.fileHandleForWriting.write(inputData)
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let exists = FileManager.default.fileExists(atPath: statusFile.path)
        var parsed: [String: Any]?
        if exists {
            let data = try Data(contentsOf: statusFile)
            parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        return HookResult(exitCode: process.terminationStatus, status: parsed, statusFileExists: exists)
    }

    /// Convenience: run a hook for a subagent (uses subagent_id for file lookup).
    @discardableResult
    func runSubagentHook(
        _ name: String,
        sessionId: String = "parent-session",
        subagentId: String,
        input: [String: Any]? = nil,
        environment: [String: String]? = nil
    ) throws -> HookResult {
        var inputDict = input ?? [:]
        if inputDict["session_id"] == nil { inputDict["session_id"] = sessionId }
        if inputDict["subagent_id"] == nil { inputDict["subagent_id"] = subagentId }

        let inputData = try JSONSerialization.data(withJSONObject: inputDict)
        let statusFile = statusDir.appendingPathComponent("\(subagentId).json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["\(hooksDir)/\(name)"]

        var env: [String: String] = [
            "HOME": tempHome.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "PPID": "99999",
        ]
        if let extra = environment { env.merge(extra) { _, new in new } }
        process.environment = env

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        stdin.fileHandleForWriting.write(inputData)
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let exists = FileManager.default.fileExists(atPath: statusFile.path)
        var parsed: [String: Any]?
        if exists {
            let data = try Data(contentsOf: statusFile)
            parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        return HookResult(exitCode: process.terminationStatus, status: parsed, statusFileExists: exists)
    }
}
