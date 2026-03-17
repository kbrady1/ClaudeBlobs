import Foundation

struct HookInstaller {
    let settingsPath: URL
    let hooksDir: String

    static let hookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse",
        "Stop", "PermissionRequest", "Notification", "SessionEnd",
        "SubagentStart", "SubagentStop", "PostToolUse",
        "TaskCompleted", "PreCompact", "PostCompact"
    ]

    static let hookFileNames: [String: String] = [
        "SessionStart": "hook-session-start.sh",
        "UserPromptSubmit": "hook-user-prompt.sh",
        "PreToolUse": "hook-pre-tool.sh",
        "Stop": "hook-stop.sh",
        "PermissionRequest": "hook-permission.sh",
        "Notification": "hook-notification.sh",
        "SessionEnd": "hook-session-end.sh",
        "SubagentStart": "hook-subagent-start.sh",
        "SubagentStop": "hook-subagent-stop.sh",
        "PostToolUse": "hook-post-tool.sh",
        "TaskCompleted": "hook-task-completed.sh",
        "PreCompact": "hook-pre-compact.sh",
        "PostCompact": "hook-post-compact.sh",
    ]

    init(settingsPath: URL? = nil, hooksDir: String? = nil) {
        self.settingsPath = settingsPath
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json")
        self.hooksDir = hooksDir
            ?? Bundle.main.resourcePath.map { $0 + "/hooks" }
            ?? "/usr/local/share/Claudblobs/hooks"
    }

    func install() throws {
        var settings = try loadSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in Self.hookEvents {
            guard let fileName = Self.hookFileNames[event] else { continue }
            let command = "\(hooksDir)/\(fileName)"
            var eventHooks = hooks[event] as? [[String: Any]] ?? []

            // Remove any existing Claudblobs hooks for this event (from any build path)
            eventHooks.removeAll { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { cmd in
                    guard let c = cmd["command"] as? String else { return false }
                    return c.hasSuffix("/\(fileName)") && c.contains("Claudblobs")
                }
            }

            // Add the hook with the current path
            eventHooks.append([
                "matcher": "",
                "hooks": [["type": "command", "command": command]]
            ])
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    func uninstall() throws {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in Self.hookEvents {
            guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
            // Remove entries from any Claudblobs build path
            eventHooks.removeAll { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { cmd in
                    guard let command = cmd["command"] as? String else { return false }
                    return command.contains("Claudblobs")
                }
            }
            // Also clean up any old-format entries (bare command at top level)
            eventHooks.removeAll { entry in
                guard let cmd = entry["command"] as? String, entry["matcher"] == nil else { return false }
                return cmd.contains("Claudblobs")
            }
            if eventHooks.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventHooks
            }
        }

        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    private func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsPath)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func saveSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: settingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsPath, options: .atomic)
    }
}
