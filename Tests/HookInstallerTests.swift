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
            #expect(eventHooks[0]["matcher"] as? String == "")
            let innerHooks = eventHooks[0]["hooks"] as! [[String: Any]]
            #expect(innerHooks.count == 1)
            #expect(innerHooks[0]["type"] as? String == "command")
            #expect((innerHooks[0]["command"] as? String)?.hasPrefix("/fake/hooks/") == true)
        }
    }

    @Test("preservesExistingHooks")
    func preservesExistingHooks() throws {
        let path = settingsPath()
        let initial: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["matcher": "", "hooks": [["type": "command", "command": "echo existing-hook"]]]
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
        let firstInner = (submitHooks[0]["hooks"] as! [[String: Any]])[0]
        #expect(firstInner["command"] as? String == "echo existing-hook")
        let secondInner = (submitHooks[1]["hooks"] as! [[String: Any]])[0]
        #expect(secondInner["command"] as? String == "/fake/hooks/hook-user-prompt.sh")
    }

    @Test("isIdempotent")
    func isIdempotent() throws {
        let path = settingsPath()
        try "{}".write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/ClaudeAgentHUD/hooks")
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
                    ["matcher": "", "hooks": [["type": "command", "command": "echo existing-hook"]]],
                    ["matcher": "", "hooks": [["type": "command", "command": "/path/to/ClaudeAgentHUD.app/hooks/hook-user-prompt.sh"]]]
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
        let innerHooks = (submitHooks[0]["hooks"] as! [[String: Any]])[0]
        #expect(innerHooks["command"] as? String == "echo existing-hook")
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
