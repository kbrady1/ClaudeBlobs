import Foundation

/// Reads `.git` directly (worktree-aware); no git binary.
struct RepoInfo: Equatable {
    let name: String
    let branch: String?

    var label: String {
        guard let branch, !branch.isEmpty else { return name }
        return "\(name) · \(branch)"
    }

    private static var cache: [String: (info: RepoInfo?, at: Date)] = [:]
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 30

    /// 30s TTL because the branch can change.
    static func resolve(cwd: String) -> RepoInfo? {
        cacheLock.lock()
        if let entry = cache[cwd], Date().timeIntervalSince(entry.at) < cacheTTL {
            cacheLock.unlock()
            return entry.info
        }
        cacheLock.unlock()
        let info = resolveUncached(cwd: cwd)
        cacheLock.lock()
        cache[cwd] = (info, Date())
        cacheLock.unlock()
        return info
    }

    static func resolveUncached(cwd: String, fileManager: FileManager = .default) -> RepoInfo? {
        guard let dotGit = findDotGit(from: cwd, fileManager: fileManager) else { return nil }
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: dotGit, isDirectory: &isDir)

        let headDir: String
        let mainGitDir: String
        if isDir.boolValue {
            headDir = dotGit
            mainGitDir = dotGit
        } else {
            // Linked worktree: ".git" is a file "gitdir: /repo/.git/worktrees/<name>"
            guard let contents = try? String(contentsOfFile: dotGit, encoding: .utf8),
                  let line = contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else {
                return nil
            }
            var path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            if !path.hasPrefix("/") {
                path = ((dotGit as NSString).deletingLastPathComponent as NSString).appendingPathComponent(path)
            }
            headDir = (path as NSString).standardizingPath
            if let range = headDir.range(of: "/.git/worktrees/") {
                mainGitDir = String(headDir[..<range.lowerBound]) + "/.git"
            } else {
                mainGitDir = headDir
            }
        }

        let name = repoName(mainGitDir: mainGitDir)
        let branch = currentBranch(headDir: headDir)
        return RepoInfo(name: name, branch: branch)
    }

    static func findDotGit(from cwd: String, fileManager: FileManager) -> String? {
        var current = (cwd as NSString).standardizingPath
        while true {
            let candidate = (current as NSString).appendingPathComponent(".git")
            if fileManager.fileExists(atPath: candidate) { return candidate }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }

    static func repoName(mainGitDir: String) -> String {
        let configPath = (mainGitDir as NSString).appendingPathComponent("config")
        if let config = try? String(contentsOfFile: configPath, encoding: .utf8),
           let url = originURL(in: config),
           let name = repoName(fromRemoteURL: url) {
            return name
        }
        return ((mainGitDir as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    static func originURL(in config: String) -> String? {
        var inOrigin = false
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
                continue
            }
            if inOrigin, line.hasPrefix("url") , let eq = line.firstIndex(of: "=") {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func repoName(fromRemoteURL url: String) -> String? {
        var path = url
        if let colon = path.range(of: ":"), !path.contains("://") {
            path = String(path[colon.upperBound...])
        } else if let schemeEnd = path.range(of: "://") {
            path = String(path[schemeEnd.upperBound...])
            if let slash = path.firstIndex(of: "/") { path = String(path[path.index(after: slash)...]) }
        }
        if path.hasSuffix(".git") { path.removeLast(4) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/")
        guard let last = parts.last, !last.isEmpty else { return nil }
        if parts.count >= 2 { return "\(parts[parts.count - 2])/\(last)" }
        return String(last)
    }

    static func currentBranch(headDir: String) -> String? {
        let headPath = (headDir as NSString).appendingPathComponent("HEAD")
        guard let head = try? String(contentsOfFile: headPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if head.hasPrefix("ref: refs/heads/") {
            return String(head.dropFirst("ref: refs/heads/".count))
        }
        if head.hasPrefix("ref: ") { return String(head.dropFirst(5)) }
        return head.count >= 7 ? String(head.prefix(7)) : head  // detached
    }
}
