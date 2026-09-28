import Foundation

/// Extra Claude Code `settings.json` paths to install hooks into, beyond the
/// default `~/.claude/settings.json`. Backs setups like `CLAUDE_CONFIG_DIR`-based
/// second profiles (e.g. `claude-neighbor`).
struct HookConfigLocations {
    let fileURL: URL

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ClaudeBlobs/hook-config-locations.json")
    }

    static var defaultSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    /// The default location plus every extra location, in order, with duplicates removed.
    func allSettingsPaths() -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for path in [Self.defaultSettingsPath] + extraSettingsPaths() {
            let normalized = path.standardizedFileURL.path
            guard seen.insert(normalized).inserted else { continue }
            result.append(path)
        }
        return result
    }

    func extraSettingsPaths() -> [URL] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    func addExtraSettingsPath(_ path: URL) throws {
        var paths = extraSettingsPaths()
        let normalized = path.standardizedFileURL.path
        guard !paths.contains(where: { $0.standardizedFileURL.path == normalized }) else { return }
        paths.append(path)
        try save(paths)
    }

    func removeExtraSettingsPath(_ path: URL) throws {
        let normalized = path.standardizedFileURL.path
        let paths = extraSettingsPaths().filter { $0.standardizedFileURL.path != normalized }
        try save(paths)
    }

    private func save(_ paths: [URL]) throws {
        let strings = paths.map(\.path)
        let data = try JSONEncoder().encode(strings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
