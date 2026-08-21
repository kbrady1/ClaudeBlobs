import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("RepoInfo")
struct RepoInfoTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("repo-\(UUID().uuidString)")

    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func resolvesMainCheckoutWithOrigin() throws {
        try write("main/.git/HEAD", "ref: refs/heads/feature/x\n")
        try write("main/.git/config", "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = git@github.com:Neighbor/rails-api.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("main/app/models"), withIntermediateDirectories: true)
        let info = RepoInfo.resolveUncached(cwd: root.appendingPathComponent("main/app/models").path)
        #expect(info == RepoInfo(name: "Neighbor/rails-api", branch: "feature/x"))
        #expect(info?.label == "Neighbor/rails-api · feature/x")
    }

    @Test func resolvesLinkedWorktree() throws {
        try write("main/.git/HEAD", "ref: refs/heads/main\n")
        try write("main/.git/config", "[remote \"origin\"]\n\turl = https://github.com/kentbrady/ClaudeBlobs\n")
        try write("main/.git/worktrees/wt1/HEAD", "ref: refs/heads/rare-ursinia\n")
        try write("wt/.git", "gitdir: \(root.path)/main/.git/worktrees/wt1\n")
        let info = RepoInfo.resolveUncached(cwd: root.appendingPathComponent("wt").path)
        #expect(info == RepoInfo(name: "kentbrady/ClaudeBlobs", branch: "rare-ursinia"))
    }

    @Test func fallsBackToFolderNameAndDetachedHead() throws {
        try write("proj/.git/HEAD", "0123456789abcdef0123456789abcdef01234567\n")
        let info = RepoInfo.resolveUncached(cwd: root.appendingPathComponent("proj").path)
        #expect(info == RepoInfo(name: "proj", branch: "0123456"))
    }

    @Test func returnsNilOutsideRepo() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plain"), withIntermediateDirectories: true)
        #expect(RepoInfo.resolveUncached(cwd: root.appendingPathComponent("plain").path) == nil)
    }

    @Test func remoteURLParsing() {
        #expect(RepoInfo.repoName(fromRemoteURL: "git@github.com:Org/repo.git") == "Org/repo")
        #expect(RepoInfo.repoName(fromRemoteURL: "https://github.com/Org/repo") == "Org/repo")
        #expect(RepoInfo.repoName(fromRemoteURL: "ssh://git@host/Org/repo.git") == "Org/repo")
    }
}

@Suite("SessionHistoryStore")
struct SessionHistoryStoreTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-\(UUID().uuidString)/history.json")

    @Test func upsertsEndsAndPrunes() {
        let store = SessionHistoryStore(fileURL: fileURL)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Agent.fixture(sessionId: "a", pid: 1, cwd: "/tmp/x", createdAt: Int64(t0.timeIntervalSince1970 * 1000) - 60_000)
        let b = Agent.fixture(sessionId: "b", pid: 2, cwd: nil)
        let kid = Agent.fixture(sessionId: "kid", pid: 0, parentSessionId: "a")

        store.observe(agents: [a, b, kid], tagsFor: { $0 == "a" ? ["research"] : [] }, now: t0)
        #expect(store.records.count == 2)
        #expect(store.records["a"]?.tagIds == ["research"])
        #expect(store.records["a"]?.firstSeenAt == t0.addingTimeInterval(-60))
        #expect(store.records["kid"] == nil)

        let t1 = t0.addingTimeInterval(600)
        store.observe(agents: [a], tagsFor: { _ in [] }, now: t1)
        #expect(store.records["b"]?.endedAt == t1)
        #expect(store.records["a"]?.isActive == true)

        // Beyond retention the record is dropped.
        let t2 = t0.addingTimeInterval(91 * 86400)
        store.observe(agents: [], tagsFor: { _ in [] }, now: t2)
        #expect(store.records.isEmpty)
    }

    @Test func refreshTagsOnlyTouchesActive() {
        let store = SessionHistoryStore(fileURL: fileURL)
        let t0 = Date()
        store.observe(agents: [Agent.fixture(sessionId: "a", pid: 1), Agent.fixture(sessionId: "b", pid: 2)], tagsFor: { _ in [] }, now: t0)
        store.observe(agents: [Agent.fixture(sessionId: "a", pid: 1)], tagsFor: { _ in [] }, now: t0.addingTimeInterval(1))
        store.refreshTags { _ in ["core-task"] }
        #expect(store.records["a"]?.tagIds == ["core-task"])
        #expect(store.records["b"]?.tagIds == [])
    }

    @Test func persistsAndQueriesByRange() {
        let now = Date()
        do {
            let store = SessionHistoryStore(fileURL: fileURL)
            store.observe(agents: [Agent.fixture(sessionId: "old", pid: 1)], tagsFor: { _ in [] }, now: now.addingTimeInterval(-40 * 86400))
            store.observe(agents: [Agent.fixture(sessionId: "new", pid: 2)], tagsFor: { _ in [] }, now: now.addingTimeInterval(-2 * 86400))
            store.save()
        }
        let reloaded = SessionHistoryStore(fileURL: fileURL)
        #expect(reloaded.records.count == 2)
        #expect(reloaded.records(in: .week, now: now).map(\.sessionId) == ["new"])
        #expect(reloaded.records(in: .quarter, now: now).map(\.sessionId) == ["old", "new"])
    }

    @Test func statsAggregate() {
        let cal = Calendar(identifier: .gregorian)
        let day0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func rec(_ id: String, day: Int, tags: [String], repo: String?, minutes: Int?) -> SessionRecord {
            let start = day0.addingTimeInterval(TimeInterval(day) * 86400 + 3600)
            return SessionRecord(sessionId: id, provider: .claudeCode, name: id, cwd: nil, repo: repo,
                                 firstSeenAt: start, lastSeenAt: start,
                                 endedAt: minutes.map { start.addingTimeInterval(TimeInterval($0) * 60) },
                                 tagIds: tags, firstPrompt: nil)
        }
        let records = [
            rec("1", day: 0, tags: ["core-task", "research"], repo: "a/x", minutes: 10),
            rec("2", day: 0, tags: [], repo: "a/x", minutes: 30),
            rec("3", day: 2, tags: ["research"], repo: "b/y", minutes: nil),
        ]
        let stats = HistoryStats.compute(records: records, tagOrder: ["core-task", "research"], calendar: cal)
        #expect(stats.total == 3)
        #expect(stats.active == 1)
        #expect(stats.activeDays == 2)
        #expect(stats.perTag == [.init(key: "core-task", count: 1), .init(key: "research", count: 2), .init(key: "untagged", count: 1)])
        #expect(stats.perRepo.first == .init(key: "a/x", count: 2))
        #expect(stats.medianDurationMinutes == 30)
        // Day 0 stacks: core-task (primary of "1") + untagged ("2") — sums to 2 sessions.
        let day0Buckets = stats.perDay.filter { $0.day == day0 }
        #expect(day0Buckets.map(\.group) == ["core-task", "untagged"])
        #expect(day0Buckets.map(\.count).reduce(0, +) == 2)
    }
}


@Suite("BoardStats")
struct BoardStatsTests {
    @Test func dwellsAreTrackedAndClosed() {
        let store = SessionHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("bs-\(UUID().uuidString).json"))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Agent.fixture(sessionId: "a", pid: 1)
        store.observe(agents: [a], tagsFor: { _ in [] }, columnFor: { _ in .working }, now: t0)
        #expect(store.records["a"]?.dwells.isEmpty == true)
        store.observe(agents: [a], tagsFor: { _ in [] }, columnFor: { _ in .idle }, now: t0.addingTimeInterval(10))
        #expect(store.records["a"]?.dwells.count == 1)
        store.observe(agents: [a], tagsFor: { _ in [] }, columnFor: { _ in .idle }, now: t0.addingTimeInterval(20))
        #expect(store.records["a"]?.dwells.count == 1)  // still the same open episode
        store.observe(agents: [a], tagsFor: { _ in [] }, columnFor: { _ in .needsAttention }, now: t0.addingTimeInterval(70))
        #expect(store.records["a"]?.dwells.map(\.column) == [.idle, .needsAttention])
        #expect(store.records["a"]?.dwells[0].end == t0.addingTimeInterval(70))
        store.observe(agents: [], tagsFor: { _ in [] }, now: t0.addingTimeInterval(100))
        #expect(store.records["a"]?.dwells[1].end == t0.addingTimeInterval(100))

        // Pin the calendar: 1_700_000_000 is a Tuesday afternoon in Denver but evening in UTC.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        let stats = BoardStats.compute(
            records: Array(store.records.values), window: 86400, tagOrder: [],
            now: t0.addingTimeInterval(100), workingHours: WorkingHours(calendar: calendar)
        )
        #expect(stats.idleWait?.max == 60)
        #expect(stats.attentionWait?.median == 30)
        #expect(stats.sessions == 1)
    }

    @Test func concurrencyAndSpread() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func rec(_ id: String, start: TimeInterval, end: TimeInterval?, tags: [String] = []) -> SessionRecord {
            SessionRecord(sessionId: id, provider: .claudeCode, name: id, cwd: nil, repo: nil,
                          firstSeenAt: t0.addingTimeInterval(start), lastSeenAt: t0.addingTimeInterval(end ?? 3600),
                          endedAt: end.map { t0.addingTimeInterval($0) }, tagIds: tags, firstPrompt: nil)
        }
        // Window = 1 hour ending at t0+3600. Three sessions overlap during [1800, 2400).
        let records = [
            rec("a", start: 0, end: 2400, tags: ["core-task"]),
            rec("b", start: 1800, end: 3000, tags: ["core-task", "research"]),
            rec("c", start: 1800, end: nil),
        ]
        let stats = BoardStats.compute(records: records, window: 3600, tagOrder: ["core-task", "research"], now: t0.addingTimeInterval(3600))
        #expect(stats.maxConcurrent == 3)
        // a: 2400s, b: 1200s, c: 1800s → 5400 session-seconds over 3600s = 1.5
        #expect(abs(stats.meanConcurrent - 1.5) < 0.001)
        #expect(stats.byTag.map(\.key) == ["core-task", "research", "untagged"])
        #expect(stats.byTag.map(\.count) == [2, 1, 1])
        #expect(stats.idleWait == nil)

        let concurrency = BoardStats.concurrencySeries(records: records, window: 3600, step: 600, now: t0.addingTimeInterval(3600))
        #expect(concurrency.count == 7)
        #expect(concurrency.map(\.value) == [1, 1, 1, 3, 2, 1, 1])
        let starts = BoardStats.startsSeries(records: records, window: 3600, step: 1800, now: t0.addingTimeInterval(3600))
        #expect(starts.map(\.value) == [1, 2])

        let spread = BoardStats.Spread.from([10, 20, 30, 40])
        #expect(spread?.median == 30)
        #expect(spread?.p75 == 40)
        #expect(spread?.mean == 25)
        #expect(spread?.max == 40)
    }
}
