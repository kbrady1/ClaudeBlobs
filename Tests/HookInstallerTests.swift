import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("HookInstaller")
struct HookInstallerTests {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hud-test-\(UUID().uuidString)")

    func settingsPath() -> URL {
        tmpDir.appendingPathComponent("settings.json")
    }

    init() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    @Test("installsHooksIntoEmptySettings")
    func installsHooksIntoEmptySettings() throws {
        let path = settingsPath()
        try "{}".write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        let data = try Data(contentsOf: path)
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        #expect(hooks.count == 7)
        for event in HookInstaller.hookEvents {
            let eventHooks = hooks[event] as! [[String: Any]]
            #expect(eventHooks.count == 1)
            #expect(eventHooks[0]["type"] as? String == "command")
            #expect((eventHooks[0]["command"] as? String)?.hasPrefix("/fake/hooks/") == true)
        }
    }

    @Test("preservesExistingHooks")
    func preservesExistingHooks() throws {
        let path = settingsPath()
        let initial: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["type": "command", "command": "echo existing-hook"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: initial, options: [])
        try data.write(to: path)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        let result = try Data(contentsOf: path)
        let settings = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let submitHooks = hooks["UserPromptSubmit"] as! [[String: Any]]

        #expect(submitHooks.count == 2)
        #expect(submitHooks[0]["command"] as? String == "echo existing-hook")
        #expect(submitHooks[1]["command"] as? String == "/fake/hooks/hook-user-prompt.sh")
    }

    @Test("isIdempotent")
    func isIdempotent() throws {
        let path = settingsPath()
        try "{}".write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()
        try installer.install()

        let data = try Data(contentsOf: path)
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for event in HookInstaller.hookEvents {
            let eventHooks = hooks[event] as! [[String: Any]]
            #expect(eventHooks.count == 1)
        }
    }

    @Test("uninstallRemovesOnlyHUDHooks")
    func uninstallRemovesOnlyHUDHooks() throws {
        let path = settingsPath()
        let initial: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["type": "command", "command": "echo existing-hook"],
                    ["type": "command", "command": "/fake/hooks/hook-user-prompt.sh"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: initial, options: [])
        try data.write(to: path)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.uninstall()

        let result = try Data(contentsOf: path)
        let settings = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let submitHooks = hooks["UserPromptSubmit"] as! [[String: Any]]

        #expect(submitHooks.count == 1)
        #expect(submitHooks[0]["command"] as? String == "echo existing-hook")
    }

    @Test("createsSettingsFileIfMissing")
    func createsSettingsFileIfMissing() throws {
        let path = tmpDir.appendingPathComponent("subdir/settings.json")

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        #expect(FileManager.default.fileExists(atPath: path.path))

        let data = try Data(contentsOf: path)
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        #expect(hooks.count == 7)
    }
}
