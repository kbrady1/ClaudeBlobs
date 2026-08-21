import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("TagStore")
struct TagStoreTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("tagstore-test-\(UUID().uuidString)/tags.json")

    @Test func startsWithPresets() {
        let store = TagStore(fileURL: fileURL)
        #expect(store.tags == AgentTag.presets)
        #expect(store.tags.map(\.id).contains("core-task"))
        #expect(store.tags.map(\.id).contains("orchestrator"))
    }

    @Test func addTagBuildsSlugAndRejectsDuplicates() {
        let store = TagStore(fileURL: fileURL)
        let tag = store.addTag(name: "Pair Programming!", description: "d", colorHex: "#FFFFFF")
        #expect(tag?.id == "pair-programming")
        #expect(store.addTag(name: "pair programming", description: "", colorHex: "#000000") == nil)
        #expect(store.addTag(name: "   ", description: "", colorHex: "#000000") == nil)
    }

    @Test func toggleCyclesAbsentToConfirmedToAbsent() {
        let store = TagStore(fileURL: fileURL)
        store.toggleTag("research", on: "s1")
        #expect(store.source(of: "research", on: "s1") == .confirmed)
        store.toggleTag("research", on: "s1")
        #expect(store.source(of: "research", on: "s1") == nil)
    }

    @Test func toggleConfirmsInferredTag() {
        let store = TagStore(fileURL: fileURL)
        store.beginInference(sessionId: "s1")
        store.finishInference(sessionId: "s1", tagId: "code-review")
        #expect(store.source(of: "code-review", on: "s1") == .inferred)
        store.toggleTag("code-review", on: "s1")
        #expect(store.source(of: "code-review", on: "s1") == .confirmed)
    }

    @Test func inferenceDoesNotOverrideConfirmed() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("research", on: "s1")
        store.beginInference(sessionId: "s1")
        store.finishInference(sessionId: "s1", tagId: "research")
        #expect(store.source(of: "research", on: "s1") == .confirmed)
    }

    @Test func needsInferenceRules() {
        let store = TagStore(fileURL: fileURL)
        #expect(store.needsInference(sessionId: "s1"))
        store.beginInference(sessionId: "s1")
        #expect(!store.needsInference(sessionId: "s1"))
        store.finishInference(sessionId: "s1", tagId: nil)
        #expect(!store.needsInference(sessionId: "s1"))

        store.confirmTag("research", on: "s2")
        #expect(!store.needsInference(sessionId: "s2"))

        store.inferenceEnabled = false
        #expect(!store.needsInference(sessionId: "s3"))
    }

    @Test func resetInferenceDropsInferredOnly() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("research", on: "s1")
        store.beginInference(sessionId: "s1")
        store.finishInference(sessionId: "s1", tagId: "side-task")
        store.resetInference(sessionId: "s1")
        #expect(store.source(of: "research", on: "s1") == .confirmed)
        #expect(store.source(of: "side-task", on: "s1") == nil)
        #expect(!store.inferenceAttempted.contains("s1"))
    }

    @Test func failInferenceRecordsError() {
        let store = TagStore(fileURL: fileURL)
        store.beginInference(sessionId: "s1")
        store.failInference(sessionId: "s1", error: "boom")
        #expect(store.inferenceErrors["s1"] == "boom")
        #expect(!store.inferringSessionIds.contains("s1"))
        #expect(store.inferenceAttempted.contains("s1"))
    }

    @Test func removeTagStripsAssignmentsAndFilter() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("research", on: "s1")
        store.toggleFilter(tagId: "research")
        store.removeTag(id: "research")
        #expect(store.tag(id: "research") == nil)
        #expect(store.assignments(for: "s1").isEmpty)
        #expect(!store.activeFilterTagIds.contains("research"))
    }

    @Test func filterSemantics() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("research", on: "tagged")
        store.confirmTag("side-task", on: "other")

        // No filter: everything passes.
        #expect(store.matchesFilter(sessionId: "tagged"))
        #expect(store.matchesFilter(sessionId: "untagged"))

        store.toggleFilter(tagId: "research")
        #expect(store.matchesFilter(sessionId: "tagged"))
        #expect(!store.matchesFilter(sessionId: "other"))
        #expect(!store.matchesFilter(sessionId: "untagged"))

        store.toggleUntaggedFilter()
        #expect(store.matchesFilter(sessionId: "untagged"))
        #expect(!store.matchesFilter(sessionId: "other"))

        store.clearFilter()
        #expect(!store.isFilterActive)
        #expect(store.matchesFilter(sessionId: "other"))
    }

    @Test func persistsAcrossInstances() {
        do {
            let store = TagStore(fileURL: fileURL)
            store.addTag(name: "Custom", description: "desc", colorHex: "#123456")
            store.confirmTag("custom", on: "s1")
            store.beginInference(sessionId: "s2")
            store.finishInference(sessionId: "s2", tagId: "research")
            store.toggleFilter(tagId: "custom")
            store.toggleUntaggedFilter()
            store.inferenceEnabled = false
        }
        let reloaded = TagStore(fileURL: fileURL)
        #expect(reloaded.tag(id: "custom")?.description == "desc")
        #expect(reloaded.source(of: "custom", on: "s1") == .confirmed)
        #expect(reloaded.source(of: "research", on: "s2") == .inferred)
        #expect(reloaded.activeFilterTagIds == ["custom"])
        #expect(reloaded.filterUntagged)
        #expect(reloaded.inferenceAttempted.contains("s2"))
        #expect(!reloaded.inferenceEnabled)
    }

    @Test func pruneForgetsDeadSessions() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("research", on: "live")
        store.confirmTag("research", on: "dead")
        store.beginInference(sessionId: "dead2")
        store.finishInference(sessionId: "dead2", tagId: nil)
        store.prune(liveSessionIds: ["live"])
        #expect(!store.assignments(for: "live").isEmpty)
        #expect(store.assignments(for: "dead").isEmpty)
        #expect(!store.inferenceAttempted.contains("dead2"))
    }

    @Test func resolvedTagsFollowDefinitionOrder() {
        let store = TagStore(fileURL: fileURL)
        store.confirmTag("orchestrator", on: "s1")
        store.confirmTag("core-task", on: "s1")
        #expect(store.resolvedTags(for: "s1").map(\.tag.id) == ["core-task", "orchestrator"])
    }

    @Test func corruptFileIsQuarantinedBeforeReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tags.json")
        try Data("{not json".utf8).write(to: url)
        let store = TagStore(fileURL: url)
        #expect(store.tags == AgentTag.presets)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tags.corrupt.json").path))
    }
}
