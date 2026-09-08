import Foundation

/// Fetches Superset workspace names via `superset ws list --json`, so the
/// board can show a workspace's human-chosen name (e.g. "Fix login bug")
/// instead of its generated branch name (e.g. "fix-login-bug-a1b2").
enum SupersetWorkspaceLookup {
    /// Workspace ID -> workspace name.
    static func fetchNames() -> [String: String] {
        guard let supersetPath = ExecutablePathResolver.resolve("superset") else {
            return [:]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: supersetPath)
        process.arguments = ["ws", "list", "--json"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutablePathResolver.enrichedPath(base: env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var names: [String: String] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { continue }
            names[id] = name
        }
        return names
    }
}
