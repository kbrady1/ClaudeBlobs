import Foundation

/// Resolves CLI executables that live outside the launchd PATH GUI apps start
/// with (`/usr/bin:/bin:/usr/sbin:/sbin`). A login shell alone (`zsh -l`)
/// isn't enough: on this machine PATH entries like `~/.local/bin` are set in
/// `~/.zshrc`, which only an interactive shell (`-i`) sources.
enum ExecutablePathResolver {
    private static var cache = [String: String]()
    private static let lock = NSLock()

    /// Extra directories checked before falling back to an interactive shell.
    private static var candidateDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.superset/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
    }

    /// Absolute path to `name`, or nil if it can't be found anywhere. Cached
    /// per name for the life of the process; the interactive-shell fallback
    /// is slow (~1-2s) so it only runs once.
    static func resolve(_ name: String) -> String? {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        for dir in candidateDirectories {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                store(name, path)
                return path
            }
        }
        if let found = resolveViaLoginShell(name) {
            store(name, found)
            return found
        }
        return nil
    }

    /// `base` with the known install directories prepended, deduplicated.
    /// Needed because some shims (e.g. Superset's `claude` wrapper) re-walk
    /// `$PATH` themselves at runtime, so resolving to an absolute path isn't
    /// enough on its own.
    static func enrichedPath(base: String) -> String {
        let existing = base.split(separator: ":").map(String.init)
        let extra = candidateDirectories.filter { !existing.contains($0) }
        return (extra + existing).joined(separator: ":")
    }

    private static func resolveViaLoginShell(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "command -v \(name)"]
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func store(_ name: String, _ path: String) {
        lock.lock()
        cache[name] = path
        lock.unlock()
    }
}
