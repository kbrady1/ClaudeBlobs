import Foundation
import Combine

struct SessionRecord: Codable, Equatable, Identifiable {
    let sessionId: String
    var provider: AgentProvider
    var name: String
    var cwd: String?
    var repo: String?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var endedAt: Date?
    var tagIds: [String]
    var firstPrompt: String?
    var dwells: [Dwell] = []

    struct Dwell: Codable, Equatable {
        let column: BoardColumn
        let start: Date
        var end: Date?
    }

    var id: String { sessionId }
    var isActive: Bool { endedAt == nil }

    init(sessionId: String, provider: AgentProvider, name: String, cwd: String?, repo: String?,
         firstSeenAt: Date, lastSeenAt: Date, endedAt: Date?, tagIds: [String], firstPrompt: String?,
         dwells: [Dwell] = []) {
        self.sessionId = sessionId
        self.provider = provider
        self.name = name
        self.cwd = cwd
        self.repo = repo
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.endedAt = endedAt
        self.tagIds = tagIds
        self.firstPrompt = firstPrompt
        self.dwells = dwells
    }

}

extension BoardColumn: Codable {}

enum HistoryRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var label: String { "\(rawValue) days" }
    var days: Int { rawValue }
}

final class SessionHistoryStore: ObservableObject {
    @Published private(set) var records: [String: SessionRecord] = [:]

    private let fileURL: URL
    private let retentionDays = 90
    private var cancellables = Set<AnyCancellable>()
    private var saveTimer: DispatchWorkItem?

    private struct Snapshot: Codable {
        var records: [SessionRecord]
    }

    static var defaultFileURL: URL {
        TagStore.defaultFileURL.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    // MARK: - Wiring

    func start(agentStore: AgentStore, tagStore: TagStore) {
        // Snoozes change columns without an agents change; the timer catches clock-driven changes (Monitor expiry).
        Publishers.Merge3(
            agentStore.$agents.map { _ in () },
            agentStore.$snoozedSessionIds.map { _ in () },
            Timer.publish(every: 30, on: .main, in: .common).autoconnect().map { _ in () }
        )
            // Throttle, not debounce: busy status files never go quiet; end-of-session detection lags at most 2s.
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self, weak agentStore, weak tagStore] in
                guard let self, let agentStore, let tagStore else { return }
                self.observe(
                    agents: agentStore.agents,
                    customNames: agentStore.customNames,
                    tagsFor: { tagStore.assignments(for: $0).map(\.tagId) },
                    columnFor: { agent in
                        BoardModel.column(
                            for: agent,
                            effectiveStatus: Agent.effectiveStatus(of: agent, children: agentStore.children(of: agent.id)),
                            isSnoozed: agentStore.snoozedSessionIds.contains(agent.id),
                            isClockBearing: BoardModel.isClockBearing(
                                agent, cronSessionIds: agentStore.cronSessionIds, dismissedClockIds: agentStore.dismissedClockIds
                            )
                        )
                    }
                )
            }
            .store(in: &cancellables)
        tagStore.$assignments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] assignments in
                self?.refreshTags { assignments[$0]?.map(\.tagId) ?? [] }
            }
            .store(in: &cancellables)
    }

    static let trackedColumns: Set<BoardColumn> = [.idle, .needsAttention]
    /// Oldest dwells are dropped past this count so one long session cannot bloat the file.
    static let maxDwellsPerRecord = 500

    func observe(
        agents: [Agent],
        customNames: [String: String] = [:],
        tagsFor: (String) -> [String],
        columnFor: (Agent) -> BoardColumn = { _ in .working },
        now: Date = Date()
    ) {
        guard !agents.isEmpty || !records.isEmpty else { return }
        let topLevel = agents.filter { $0.parentSessionId == nil && $0.pid != 0 }
        var updated = records
        var live: Set<String> = []

        for agent in topLevel {
            live.insert(agent.sessionId)
            let firstSeen = agent.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? now
            var record = updated[agent.sessionId] ?? SessionRecord(
                sessionId: agent.sessionId,
                provider: agent.provider,
                name: customNames[agent.sessionId] ?? agent.directoryLabel,
                cwd: agent.cwd,
                repo: nil,
                firstSeenAt: firstSeen,
                lastSeenAt: now,
                endedAt: nil,
                tagIds: [],
                firstPrompt: nil
            )
            record.name = customNames[agent.sessionId] ?? agent.directoryLabel
            record.cwd = agent.cwd
            // Coarse heartbeat: avoids rewriting every record on each snapshot.
            if now.timeIntervalSince(record.lastSeenAt) >= 30 || record.endedAt != nil {
                record.lastSeenAt = now
            }
            record.endedAt = nil
            record.tagIds = tagsFor(agent.sessionId)
            if record.firstPrompt == nil, let prompt = agent.firstPrompt {
                record.firstPrompt = String(prompt.prefix(200))
            }
            if record.repo == nil, let cwd = agent.cwd {
                record.repo = RepoInfo.resolve(cwd: cwd)?.name
            }
            let column = columnFor(agent)
            if let openIndex = record.dwells.lastIndex(where: { $0.end == nil }),
               record.dwells[openIndex].column != column {
                record.dwells[openIndex].end = now
            }
            if Self.trackedColumns.contains(column), !record.dwells.contains(where: { $0.end == nil }) {
                record.dwells.append(SessionRecord.Dwell(column: column, start: now, end: nil))
                if record.dwells.count > Self.maxDwellsPerRecord {
                    record.dwells.removeFirst(record.dwells.count - Self.maxDwellsPerRecord)
                }
            }
            updated[agent.sessionId] = record
        }

        for (id, record) in updated where record.endedAt == nil && !live.contains(id) {
            updated[id]?.endedAt = now
            if let openIndex = record.dwells.lastIndex(where: { $0.end == nil }) {
                updated[id]?.dwells[openIndex].end = now
            }
        }

        let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays) * 86400)
        updated = updated.filter { $0.value.lastSeenAt >= cutoff }

        if updated != records {
            records = updated
            scheduleSave()
        }
    }

    func refreshTags(_ tagsFor: (String) -> [String]) {
        var changed = false
        for (id, record) in records where record.isActive {
            let tags = tagsFor(id)
            if tags != record.tagIds {
                records[id]?.tagIds = tags
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    // MARK: - Queries

    func records(in range: HistoryRange, now: Date = Date()) -> [SessionRecord] {
        let cutoff = now.addingTimeInterval(-TimeInterval(range.days) * 86400)
        return records.values
            .filter { $0.lastSeenAt >= cutoff }
            .sorted { $0.firstSeenAt < $1.firstSeenAt }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            CorruptFile.quarantine(fileURL, store: "SessionHistoryStore")
            return
        }
        records = Dictionary(snapshot.records.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, b in b })
    }

    /// Keeps the armed timer so a steady stream of changes still flushes every 2s.
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    func save() {
        saveTimer?.cancel()
        saveTimer = nil
        let snapshot = Snapshot(records: Array(records.values).sorted { $0.firstSeenAt < $1.firstSeenAt })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.shared.log("SessionHistoryStore save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Aggregation

struct HistoryStats: Equatable {
    struct DayBucket: Identifiable, Equatable {
        let day: Date
        let group: String   // tag id or "untagged"
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(group)" }
    }
    struct Count: Identifiable, Equatable {
        let key: String
        let count: Int
        var id: String { key }
    }

    let total: Int
    let active: Int
    let activeDays: Int
    let perDay: [DayBucket]
    let perTag: [Count]
    let perRepo: [Count]
    let medianDurationMinutes: Int?

    static let untagged = "untagged"

    /// `perDay` stacks by primary tag so stacks sum to the total; `perTag` counts a session once per tag.
    static func compute(records: [SessionRecord], tagOrder: [String], calendar: Calendar = .current) -> HistoryStats {
        var day: [Date: [String: Int]] = [:]
        var tag: [String: Int] = [:]
        var repo: [String: Int] = [:]
        var durations: [TimeInterval] = []

        for record in records {
            let start = calendar.startOfDay(for: record.firstSeenAt)
            let primary = tagOrder.first { record.tagIds.contains($0) } ?? untagged
            day[start, default: [:]][primary, default: 0] += 1
            if record.tagIds.isEmpty {
                tag[untagged, default: 0] += 1
            } else {
                for id in record.tagIds { tag[id, default: 0] += 1 }
            }
            repo[record.repo ?? "(no repo)", default: 0] += 1
            if let end = record.endedAt {
                durations.append(end.timeIntervalSince(record.firstSeenAt))
            }
        }

        let perDay = day.keys.sorted().flatMap { date -> [DayBucket] in
            let groups = day[date] ?? [:]
            let ordered = tagOrder.filter { groups[$0] != nil } + (groups[untagged] != nil ? [untagged] : [])
            return ordered.map { DayBucket(day: date, group: $0, count: groups[$0] ?? 0) }
        }
        let perTag = (tagOrder + [untagged]).compactMap { id -> Count? in
            guard let n = tag[id] else { return nil }
            return Count(key: id, count: n)
        }
        let perRepo = repo.map { Count(key: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
        let median: Int? = {
            guard !durations.isEmpty else { return nil }
            let sorted = durations.sorted()
            return Int(sorted[sorted.count / 2] / 60)
        }()

        return HistoryStats(
            total: records.count,
            active: records.filter(\.isActive).count,
            activeDays: day.count,
            perDay: perDay,
            perTag: perTag,
            perRepo: Array(perRepo.prefix(8)),
            medianDurationMinutes: median
        )
    }
}


// MARK: - Board stat line

struct BoardStats: Equatable {
    struct Spread: Equatable {
        let count: Int
        let max: TimeInterval
        let median: TimeInterval
        let p75: TimeInterval
        let mean: TimeInterval

        static func from(_ values: [TimeInterval]) -> Spread? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return Spread(
                count: sorted.count,
                max: sorted.last ?? 0,
                median: sorted[sorted.count / 2],
                p75: sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.75))],
                mean: sorted.reduce(0, +) / Double(sorted.count)
            )
        }
    }

    let window: TimeInterval
    let sessions: Int
    /// Tag-definition order; zero counts omitted.
    let byTag: [(key: String, count: Int)]
    let idleWait: Spread?
    let attentionWait: Spread?
    let maxConcurrent: Int
    let meanConcurrent: Double

    static func == (a: BoardStats, b: BoardStats) -> Bool {
        a.window == b.window && a.sessions == b.sessions && a.idleWait == b.idleWait
            && a.attentionWait == b.attentionWait && a.maxConcurrent == b.maxConcurrent
            && a.meanConcurrent == b.meanConcurrent
            && a.byTag.map(\.key) == b.byTag.map(\.key) && a.byTag.map(\.count) == b.byTag.map(\.count)
    }

    struct Sample: Identifiable, Equatable {
        let time: Date
        let value: Int
        var id: Date { time }
    }

    static func concurrencySeries(records: [SessionRecord], window: TimeInterval, step: TimeInterval, now: Date = Date()) -> [Sample] {
        let from = now.addingTimeInterval(-window)
        // Only records that overlap the window can contribute to any sample.
        let overlapping = records.filter { ($0.endedAt ?? now) > from && $0.firstSeenAt <= now }
        var samples: [Sample] = []
        var t = from
        while t <= now {
            let n = overlapping.filter { $0.firstSeenAt <= t && ($0.endedAt.map { $0 > t } ?? true) }.count
            samples.append(Sample(time: t, value: n))
            t = t.addingTimeInterval(step)
        }
        return samples
    }

    static func startsSeries(records: [SessionRecord], window: TimeInterval, step: TimeInterval, now: Date = Date()) -> [Sample] {
        let from = now.addingTimeInterval(-window)
        let bucketCount = Int((window / step).rounded(.up))
        var counts = Array(repeating: 0, count: max(1, bucketCount))
        for record in records where record.firstSeenAt >= from && record.firstSeenAt <= now {
            let index = min(counts.count - 1, Int(record.firstSeenAt.timeIntervalSince(from) / step))
            counts[index] += 1
        }
        return counts.enumerated().map { Sample(time: from.addingTimeInterval(Double($0.offset) * step), value: $0.element) }
    }

    /// Waits count working hours only (`WorkingHours`); concurrency is time-weighted over the window.
    static func compute(records: [SessionRecord], window: TimeInterval, tagOrder: [String], now: Date = Date(), workingHours: WorkingHours = .default) -> BoardStats {
        let from = now.addingTimeInterval(-window)
        let inWindow = records.filter { $0.lastSeenAt >= from }

        var tagCounts: [String: Int] = [:]
        for record in inWindow {
            if record.tagIds.isEmpty {
                tagCounts[HistoryStats.untagged, default: 0] += 1
            } else {
                for id in record.tagIds { tagCounts[id, default: 0] += 1 }
            }
        }
        let byTag = (tagOrder + [HistoryStats.untagged]).compactMap { id -> (key: String, count: Int)? in
            guard let n = tagCounts[id] else { return nil }
            return (id, n)
        }

        func waits(_ column: BoardColumn) -> [TimeInterval] {
            records.flatMap { record in
                record.dwells
                    .filter { $0.column == column && $0.start >= from }
                    .map { workingHours.activeSeconds(from: $0.start, to: $0.end ?? now) }
            }
        }

        var events: [(Date, Int)] = []
        for record in records {
            let start = max(record.firstSeenAt, from)
            let end = min(record.endedAt ?? now, now)
            guard end > start else { continue }
            events.append((start, 1))
            events.append((end, -1))
        }
        events.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var current = 0
        var peak = 0
        var weighted: Double = 0
        var last = from
        for (time, delta) in events {
            weighted += Double(current) * time.timeIntervalSince(last)
            current += delta
            peak = max(peak, current)
            last = time
        }
        weighted += Double(current) * now.timeIntervalSince(last)

        return BoardStats(
            window: window,
            sessions: inWindow.count,
            byTag: byTag,
            idleWait: Spread.from(waits(.idle)),
            attentionWait: Spread.from(waits(.needsAttention)),
            maxConcurrent: peak,
            meanConcurrent: window > 0 ? weighted / window : 0
        )
    }
}
