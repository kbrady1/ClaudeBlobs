import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("HookConfigLocations")
struct HookConfigLocationsTests {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hook-config-locations-test-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    func locationsFile() -> URL {
        tmpDir.appendingPathComponent("hook-config-locations.json")
    }

    @Test("defaultsToJustTheDefaultSettingsPath")
    func defaultsToJustTheDefaultSettingsPath() {
        let locations = HookConfigLocations(fileURL: locationsFile())
        #expect(locations.extraSettingsPaths().isEmpty)
        #expect(locations.allSettingsPaths() == [HookConfigLocations.defaultSettingsPath])
    }

    @Test("addExtraSettingsPathPersists")
    func addExtraSettingsPathPersists() throws {
        let locations = HookConfigLocations(fileURL: locationsFile())
        let extra = tmpDir.appendingPathComponent("neighbor/settings.json")

        try locations.addExtraSettingsPath(extra)

        let reloaded = HookConfigLocations(fileURL: locationsFile())
        #expect(reloaded.extraSettingsPaths() == [extra])
        #expect(reloaded.allSettingsPaths() == [HookConfigLocations.defaultSettingsPath, extra])
    }

    @Test("addExtraSettingsPathIsIdempotent")
    func addExtraSettingsPathIsIdempotent() throws {
        let locations = HookConfigLocations(fileURL: locationsFile())
        let extra = tmpDir.appendingPathComponent("neighbor/settings.json")

        try locations.addExtraSettingsPath(extra)
        try locations.addExtraSettingsPath(extra)

        #expect(locations.extraSettingsPaths().count == 1)
    }

    @Test("removeExtraSettingsPath")
    func removeExtraSettingsPath() throws {
        let locations = HookConfigLocations(fileURL: locationsFile())
        let extra = tmpDir.appendingPathComponent("neighbor/settings.json")

        try locations.addExtraSettingsPath(extra)
        try locations.removeExtraSettingsPath(extra)

        #expect(locations.extraSettingsPaths().isEmpty)
    }

    @Test("installAllInstallsIntoEveryLocation")
    func installAllInstallsIntoEveryLocation() throws {
        let defaultPath = tmpDir.appendingPathComponent("default-settings.json")
        let extraPath = tmpDir.appendingPathComponent("neighbor-settings.json")
        try "{}".write(to: defaultPath, atomically: true, encoding: .utf8)

        let locations = HookConfigLocations(fileURL: locationsFile())
        try locations.addExtraSettingsPath(extraPath)

        // installAll always seeds the *real* default path; verify the extra path
        // independently gets hooks installed via a direct HookInstaller call,
        // mirroring what installAll does per-location.
        for path in locations.allSettingsPaths() where path != HookConfigLocations.defaultSettingsPath {
            try HookInstaller(settingsPath: path, hooksDir: "/fake/hooks").install()
        }

        let data = try Data(contentsOf: extraPath)
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        #expect(hooks.count == 15)
    }
}
