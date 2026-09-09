import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("DesktopSessionIndex")
struct DesktopSessionIndexTests {
    /// The leading fields of a real Claude Desktop session file, in file order.
    private func sessionFilePrefix(
        sessionId: String,
        cliSessionId: String?,
        archived: Bool = false
    ) -> String {
        var fields = ["\"sessionId\": \"\(sessionId)\""]
        if let cliSessionId { fields.append("\"cliSessionId\": \"\(cliSessionId)\"") }
        fields.append("\"cwd\": \"/Users/test/code\"")
        fields.append("\"lastActivityAt\": 1788928438008")
        fields.append("\"isArchived\": \(archived)")
        fields.append("\"title\": \"Test session\"")
        return "{\(fields.joined(separator: ", "))"
    }

    @Test func parsesSessionAndCLIIds() {
        let entry = DesktopSessionIndex.parse(
            prefix: sessionFilePrefix(
                sessionId: "local_115a68e0-6cde-4823-9640-d17816cd0692",
                cliSessionId: "122c7a92-ff70-4790-bfe0-b097e5c41af7"
            )
        )
        #expect(entry?.sessionId == "local_115a68e0-6cde-4823-9640-d17816cd0692")
        #expect(entry?.cliSessionId == "122c7a92-ff70-4790-bfe0-b097e5c41af7")
        #expect(entry?.isArchived == false)
        #expect(entry?.isImportedCopy == false)
    }

    @Test func parsesArchivedFlag() {
        let entry = DesktopSessionIndex.parse(
            prefix: sessionFilePrefix(
                sessionId: "local_a",
                cliSessionId: "cli-a",
                archived: true
            )
        )
        #expect(entry?.isArchived == true)
    }

    /// A session Claude Desktop has spawned but never run has no cliSessionId.
    @Test func skipsSessionWithoutCLISessionId() {
        let entry = DesktopSessionIndex.parse(
            prefix: sessionFilePrefix(sessionId: "local_a", cliSessionId: nil)
        )
        #expect(entry == nil)
    }

    @Test func recognizesImportedCopyByItsDerivedId() {
        let entry = DesktopSessionIndex.parse(
            prefix: sessionFilePrefix(
                sessionId: "local_122c7a92-ff70-4790-bfe0-b097e5c41af7",
                cliSessionId: "122c7a92-ff70-4790-bfe0-b097e5c41af7"
            )
        )
        #expect(entry?.isImportedCopy == true)
    }

    @Test func picksMatchingSession() {
        let entries = [
            DesktopSessionIndex.Entry(sessionId: "local_a", cliSessionId: "cli-a", isArchived: false),
            DesktopSessionIndex.Entry(sessionId: "local_b", cliSessionId: "cli-b", isArchived: false),
        ]
        #expect(DesktopSessionIndex.pick(entries, forCLISession: "cli-b")?.sessionId == "local_b")
    }

    @Test func picksNothingForUnknownCLISession() {
        let entries = [
            DesktopSessionIndex.Entry(sessionId: "local_a", cliSessionId: "cli-a", isArchived: false)
        ]
        #expect(DesktopSessionIndex.pick(entries, forCLISession: "cli-z") == nil)
    }

    @Test func skipsArchivedSessions() {
        let entries = [
            DesktopSessionIndex.Entry(sessionId: "local_a", cliSessionId: "cli-a", isArchived: true)
        ]
        #expect(DesktopSessionIndex.pick(entries, forCLISession: "cli-a") == nil)
    }

    /// Resuming a live session once imported a duplicate of it. The native
    /// session is the one the user is looking at, so it has to win.
    @Test func prefersNativeSessionOverImportedCopy() {
        let entries = [
            DesktopSessionIndex.Entry(
                sessionId: "local_122c7a92-ff70-4790-bfe0-b097e5c41af7",
                cliSessionId: "122c7a92-ff70-4790-bfe0-b097e5c41af7",
                isArchived: false
            ),
            DesktopSessionIndex.Entry(
                sessionId: "local_115a68e0-6cde-4823-9640-d17816cd0692",
                cliSessionId: "122c7a92-ff70-4790-bfe0-b097e5c41af7",
                isArchived: false
            ),
        ]
        #expect(
            DesktopSessionIndex.pick(entries, forCLISession: "122c7a92-ff70-4790-bfe0-b097e5c41af7")?
                .sessionId == "local_115a68e0-6cde-4823-9640-d17816cd0692"
        )
    }

    @Test func loadsEntriesFromNestedAccountDirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("account-uuid/org-uuid")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try sessionFilePrefix(sessionId: "local_a", cliSessionId: "cli-a")
            .write(to: dir.appendingPathComponent("local_a.json"), atomically: true, encoding: .utf8)
        // Not a session file; must be ignored.
        try "{}".write(
            to: dir.appendingPathComponent("scheduled-tasks.json"),
            atomically: true, encoding: .utf8
        )

        let entries = DesktopSessionIndex.loadEntries(root: root)
        #expect(entries.count == 1)
        #expect(DesktopSessionIndex.localSessionId(forCLISession: "cli-a", root: root) == "local_a")
    }

    @Test func returnsNilWhenRootIsMissing() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        #expect(DesktopSessionIndex.localSessionId(forCLISession: "cli-a", root: root) == nil)
    }
}
