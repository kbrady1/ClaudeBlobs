import Foundation
import ServiceManagement

struct Uninstaller {
    let statusDir: URL
    let hookInstaller: HookInstaller

    init(
        statusDir: URL? = nil,
        hookInstaller: HookInstaller = HookInstaller()
    ) {
        self.statusDir = statusDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/agent-status")
        self.hookInstaller = hookInstaller
    }

    func uninstall() throws {
        try hookInstaller.uninstall()

        if FileManager.default.fileExists(atPath: statusDir.path) {
            try FileManager.default.removeItem(at: statusDir)
        }

        try? SMAppService.mainApp.unregister()
    }
}
