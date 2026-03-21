import XCTest
@testable import ClaudeBlobsLib

final class OpenCodeInstallerTests: XCTestCase {
    var tmpDir: URL!
    var pluginDirectory: URL!
    var pluginSourcePath: URL!
    var statusDirectory: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeBlobsTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        pluginDirectory = tmpDir.appendingPathComponent("plugins")
        pluginSourcePath = tmpDir.appendingPathComponent(OpenCodeInstaller.pluginFileName)
        statusDirectory = tmpDir.appendingPathComponent("agent-status")
        try! "export default {}\n".write(to: pluginSourcePath, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeInstaller() -> OpenCodeInstaller {
        OpenCodeInstaller(pluginDirectory: pluginDirectory, pluginSourcePath: pluginSourcePath, statusDirectory: statusDirectory)
    }

    func testInstallCopiesPluginIntoDirectory() throws {
        try makeInstaller().install()

        let installedPath = pluginDirectory.appendingPathComponent(OpenCodeInstaller.pluginFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedPath.path))
    }

    func testInstallCreatesIntermediateDirectories() throws {
        let nestedDirectory = tmpDir.appendingPathComponent("a/b/c/plugins")
        let installer = OpenCodeInstaller(pluginDirectory: nestedDirectory, pluginSourcePath: pluginSourcePath, statusDirectory: statusDirectory)

        try installer.install()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.installedPluginPath.path))
    }

    func testInstallReplacesExistingPlugin() throws {
        try makeInstaller().install()
        let installedPath = makeInstaller().installedPluginPath
        try "old plugin\n".write(to: installedPath, atomically: true, encoding: .utf8)

        try makeInstaller().install()

        let contents = try String(contentsOf: installedPath)
        XCTAssertEqual(contents, "export default {}\n")
    }

    func testUninstallRemovesInstalledPlugin() throws {
        try makeInstaller().install()

        try makeInstaller().uninstall()

        XCTAssertFalse(FileManager.default.fileExists(atPath: makeInstaller().installedPluginPath.path))
    }

    func testUninstallNoopsWhenMissing() {
        XCTAssertNoThrow(try makeInstaller().uninstall())
    }

    func testIsInstalledReflectsInstalledFile() throws {
        XCTAssertFalse(makeInstaller().isInstalled)
        try makeInstaller().install()
        XCTAssertTrue(makeInstaller().isInstalled)
        try makeInstaller().uninstall()
        XCTAssertFalse(makeInstaller().isInstalled)
    }
}
