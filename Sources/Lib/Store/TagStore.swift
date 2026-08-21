import Foundation
import Combine

final class TagStore: ObservableObject {
    @Published private(set) var tags: [AgentTag] = AgentTag.presets
    /// Keyed by `sessionId`, not `Agent.id`, to match the hooks and the transcript.
    @Published private(set) var assignments: [String: [TagAssignment]] = [:]
    /// Empty, with `filterUntagged` false, means show everything.
    @Published private(set) var activeFilterTagIds: Set<String> = []
    @Published private(set) var filterUntagged: Bool = false
    @Published private(set) var inferenceAttempted: Set<String> = []
    @Published var inferenceEnabled: Bool = true {
        didSet { save() }
    }

    // Transient, not persisted.
    @Published var inferringSessionIds: Set<String> = []
    @Published var inferenceErrors: [String: String] = [:]

    private let fileURL: URL
    private let fileManager = FileManager.default

    private struct Snapshot: Codable {
        var tags: [AgentTag]
        var assignments: [String: [TagAssignment]]
        var activeFilterTagIds: [String]
        var filterUntagged: Bool
        var inferenceAttempted: [String]
        var inferenceEnabled: Bool
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ClaudeBlobs/tags.json")
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            CorruptFile.quarantine(fileURL, store: "TagStore")
            return
        }
        tags = snapshot.tags.isEmpty ? AgentTag.presets : snapshot.tags
        assignments = snapshot.assignments
        activeFilterTagIds = Set(snapshot.activeFilterTagIds)
        filterUntagged = snapshot.filterUntagged
        inferenceAttempted = Set(snapshot.inferenceAttempted)
        inferenceEnabled = snapshot.inferenceEnabled
    }

    private func save() {
        let snapshot = Snapshot(
            tags: tags,
            assignments: assignments,
            activeFilterTagIds: Array(activeFilterTagIds).sorted(),
            filterUntagged: filterUntagged,
            inferenceAttempted: Array(inferenceAttempted).sorted(),
            inferenceEnabled: inferenceEnabled
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.shared.log("TagStore save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Tag definitions

    func tag(id: String) -> AgentTag? {
        tags.first { $0.id == id }
    }

    @discardableResult
    func addTag(name: String, description: String, colorHex: String) -> AgentTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = AgentTag.slug(from: trimmed)
        guard !slug.isEmpty, tag(id: slug) == nil else { return nil }
        let tag = AgentTag(
            id: slug,
            name: trimmed,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex
        )
        tags.append(tag)
        save()
        return tag
    }

    func updateTag(_ updated: AgentTag) {
        guard let index = tags.firstIndex(where: { $0.id == updated.id }) else { return }
        tags[index] = updated
        save()
    }

    func removeTag(id: String) {
        tags.removeAll { $0.id == id }
        for key in assignments.keys {
            assignments[key]?.removeAll { $0.tagId == id }
            if assignments[key]?.isEmpty == true { assignments.removeValue(forKey: key) }
        }
        activeFilterTagIds.remove(id)
        save()
    }

    // MARK: - Assignments

    func assignments(for sessionId: String) -> [TagAssignment] {
        assignments[sessionId] ?? []
    }

    func resolvedTags(for sessionId: String) -> [(tag: AgentTag, source: TagSource)] {
        let current = assignments(for: sessionId)
        return tags.compactMap { tag in
            guard let assignment = current.first(where: { $0.tagId == tag.id }) else { return nil }
            return (tag, assignment.source)
        }
    }

    func hasTag(_ tagId: String, on sessionId: String) -> Bool {
        assignments(for: sessionId).contains { $0.tagId == tagId }
    }

    func source(of tagId: String, on sessionId: String) -> TagSource? {
        assignments(for: sessionId).first { $0.tagId == tagId }?.source
    }

    func confirmTag(_ tagId: String, on sessionId: String) {
        guard tag(id: tagId) != nil else { return }
        var current = assignments(for: sessionId)
        if let index = current.firstIndex(where: { $0.tagId == tagId }) {
            current[index].source = .confirmed
        } else {
            current.append(TagAssignment(tagId: tagId, source: .confirmed))
        }
        assignments[sessionId] = current
        save()
    }

    func removeTag(_ tagId: String, from sessionId: String) {
        var current = assignments(for: sessionId)
        current.removeAll { $0.tagId == tagId }
        if current.isEmpty {
            assignments.removeValue(forKey: sessionId)
        } else {
            assignments[sessionId] = current
        }
        save()
    }

    func toggleTag(_ tagId: String, on sessionId: String) {
        switch source(of: tagId, on: sessionId) {
        case nil, .inferred?:
            confirmTag(tagId, on: sessionId)
        case .confirmed?:
            removeTag(tagId, from: sessionId)
        }
    }

    // MARK: - Inference bookkeeping

    func needsInference(sessionId: String) -> Bool {
        guard inferenceEnabled else { return false }
        guard !inferenceAttempted.contains(sessionId) else { return false }
        guard !inferringSessionIds.contains(sessionId) else { return false }
        return assignments(for: sessionId).isEmpty
    }

    func beginInference(sessionId: String) {
        inferringSessionIds.insert(sessionId)
        inferenceErrors.removeValue(forKey: sessionId)
    }

    func finishInference(sessionId: String, tagId: String?) {
        inferringSessionIds.remove(sessionId)
        inferenceAttempted.insert(sessionId)
        if let tagId, tag(id: tagId) != nil, !hasTag(tagId, on: sessionId) {
            var current = assignments(for: sessionId)
            current.append(TagAssignment(tagId: tagId, source: .inferred))
            assignments[sessionId] = current
        }
        save()
    }

    func failInference(sessionId: String, error: String) {
        inferringSessionIds.remove(sessionId)
        inferenceAttempted.insert(sessionId)
        inferenceErrors[sessionId] = error
        save()
    }

    func resetInference(sessionId: String) {
        var current = assignments(for: sessionId)
        current.removeAll { $0.source == .inferred }
        if current.isEmpty {
            assignments.removeValue(forKey: sessionId)
        } else {
            assignments[sessionId] = current
        }
        inferenceAttempted.remove(sessionId)
        inferenceErrors.removeValue(forKey: sessionId)
        save()
    }

    // MARK: - Filter

    var isFilterActive: Bool { !activeFilterTagIds.isEmpty || filterUntagged }

    func toggleFilter(tagId: String) {
        if activeFilterTagIds.contains(tagId) {
            activeFilterTagIds.remove(tagId)
        } else {
            activeFilterTagIds.insert(tagId)
        }
        save()
    }

    func toggleUntaggedFilter() {
        filterUntagged.toggle()
        save()
    }

    func clearFilter() {
        activeFilterTagIds = []
        filterUntagged = false
        save()
    }

    func matchesFilter(sessionId: String) -> Bool {
        guard isFilterActive else { return true }
        let current = assignments(for: sessionId)
        if current.isEmpty { return filterUntagged }
        return current.contains { activeFilterTagIds.contains($0.tagId) }
    }

    // MARK: - Cleanup

    /// Safe to forget ended sessions: their tags live on in `SessionRecord.tagIds`.
    func prune(liveSessionIds: Set<String>) {
        let staleAssignments = assignments.keys.filter { !liveSessionIds.contains($0) }
        let staleAttempts = inferenceAttempted.filter { !liveSessionIds.contains($0) }
        guard !staleAssignments.isEmpty || !staleAttempts.isEmpty else { return }
        for key in staleAssignments { assignments.removeValue(forKey: key) }
        inferenceAttempted.subtract(staleAttempts)
        for key in inferenceErrors.keys where !liveSessionIds.contains(key) {
            inferenceErrors.removeValue(forKey: key)
        }
        save()
    }
}
