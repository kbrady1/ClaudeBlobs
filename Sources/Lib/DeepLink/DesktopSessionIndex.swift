import Foundation

/// Maps a Claude Code CLI session id to the Claude Desktop session that hosts it.
///
/// Claude Desktop keeps one JSON file per session under
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<uuid>.json`.
/// Each file records its own `sessionId` (a `local_`-prefixed id) and the
/// `cliSessionId` of the Claude Code process it drives. Our status files carry
/// only the CLI session id, so this index walks that mapping backwards.
///
/// The files run to a few hundred kilobytes each, nearly all of it cached MCP
/// tool definitions. The fields we want sit in the first few hundred bytes, so
/// the scan reads a prefix of each file instead of decoding it.
struct DesktopSessionIndex {
    /// Bytes read from the head of each session file. Generous enough to cover
    /// the leading scalar fields even with long `cwd` paths, small enough that
    /// scanning every session stays cheap.
    static let prefixByteCount = 8192

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// One session file's identifying fields, as read from its JSON prefix.
    struct Entry: Equatable {
        let sessionId: String
        let cliSessionId: String
        let isArchived: Bool

        /// True when Claude Desktop created this session by importing a CLI
        /// transcript, which it names `local_<cliSessionId>`. A session Claude
        /// Desktop spawned itself gets an unrelated id instead.
        var isImportedCopy: Bool { sessionId == "local_\(cliSessionId)" }
    }

    private static func string(_ key: String, in prefix: String) -> String? {
        guard let range = prefix.range(of: "\"\(key)\"\\s*:\\s*\"[^\"]*\"", options: .regularExpression),
              let valueRange = prefix[range].range(of: "\"[^\"]*\"$", options: .regularExpression)
        else { return nil }
        return String(prefix[range][valueRange].dropFirst().dropLast())
    }

    /// Parses a session file's JSON prefix. Pure, so tests can cover it without
    /// a Claude Desktop install.
    static func parse(prefix: String) -> Entry? {
        guard let sessionId = string("sessionId", in: prefix),
              let cliSessionId = string("cliSessionId", in: prefix)
        else { return nil }
        let archived = prefix.range(of: "\"isArchived\"\\s*:\\s*true", options: .regularExpression) != nil
        return Entry(sessionId: sessionId, cliSessionId: cliSessionId, isArchived: archived)
    }

    /// Picks the desktop session to focus for a CLI session id.
    ///
    /// Archived sessions never win. When both a natively spawned session and an
    /// imported copy claim the same CLI session, the native one wins: the
    /// import is a snapshot of the transcript, while the native session is the
    /// live one the user is actually looking at.
    static func pick(_ entries: [Entry], forCLISession cliSessionId: String) -> Entry? {
        let matches = entries.filter { $0.cliSessionId == cliSessionId && !$0.isArchived }
        return matches.first(where: { !$0.isImportedCopy }) ?? matches.first
    }

    private static func readPrefix(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: prefixByteCount) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads every session file under `root` and returns the parsed entries.
    static func loadEntries(root: URL = defaultRoot) -> [Entry] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var entries: [Entry] = []
        for case let url as URL in walker {
            guard url.pathExtension == "json",
                  url.lastPathComponent.hasPrefix("local_"),
                  let prefix = readPrefix(of: url),
                  let entry = parse(prefix: prefix)
            else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// Returns the `local_`-prefixed Claude Desktop session id hosting a CLI
    /// session, or nil when no live desktop session claims it.
    static func localSessionId(forCLISession cliSessionId: String, root: URL = defaultRoot) -> String? {
        pick(loadEntries(root: root), forCLISession: cliSessionId)?.sessionId
    }
}
