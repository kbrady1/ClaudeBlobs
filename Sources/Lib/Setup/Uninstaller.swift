import Foundation
import ServiceManagement

struct Uninstaller {
    let statusDirs: [URL]
    let hookInstaller: HookInstaller
    let openCodeInstaller: OpenCodeInstaller

    init(
        statusDir: URL? = nil,
        hookInstaller: HookInstaller = HookInstaller(),
        openCodeInstaller: OpenCodeInstaller = OpenCodeInstaller()
    ) {
        self.statusDirs = [
            statusDir ?? AgentProvider.claudeCode.statusDirectory,
            AgentProvider.openCode.statusDirectory,
        ]
        self.hookInstaller = hookInstaller
        self.openCodeInstaller = openCodeInstaller
    }

    func uninstall() throws {
        try hookInstaller.uninstall()
        try? openCodeInstaller.uninstall()

        for statusDir in statusDirs where FileManager.default.fileExists(atPath: statusDir.path) {
            try FileManager.default.removeItem(at: statusDir)
        }

        try? SMAppService.mainApp.unregister()
    }
}
