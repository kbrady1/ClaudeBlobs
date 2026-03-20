import Foundation

struct OpenCodeInstaller {
    let pluginDirectory: URL
    let pluginSourcePath: URL
    let statusDirectory: URL

    static let pluginFileName = "claudeblobs-opencode.js"

    init(pluginDirectory: URL? = nil, pluginSourcePath: URL? = nil, statusDirectory: URL? = nil) {
        self.pluginDirectory = pluginDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/opencode/plugins")
        self.pluginSourcePath = pluginSourcePath
            ?? Bundle.main.resourceURL?
                .appendingPathComponent("opencode-plugin/\(Self.pluginFileName)")
            ?? URL(fileURLWithPath: "/usr/local/share/ClaudeBlobs/opencode-plugin/\(Self.pluginFileName)")
        self.statusDirectory = statusDirectory ?? AgentProvider.openCode.statusDirectory
    }

    var installedPluginPath: URL {
        pluginDirectory.appendingPathComponent(Self.pluginFileName)
    }

    func install() throws {
        guard FileManager.default.fileExists(atPath: pluginSourcePath.path) else {
            throw NSError(
                domain: "ClaudeBlobs.OpenCodeInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled OpenCode plugin not found."]
            )
        }

        try FileManager.default.createDirectory(
            at: pluginDirectory,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: installedPluginPath.path) {
            try FileManager.default.removeItem(at: installedPluginPath)
        }
        try FileManager.default.copyItem(at: pluginSourcePath, to: installedPluginPath)

        try FileManager.default.createDirectory(
            at: statusDirectory,
            withIntermediateDirectories: true
        )
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: installedPluginPath.path) {
            try FileManager.default.removeItem(at: installedPluginPath)
        }
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPluginPath.path)
    }
}
