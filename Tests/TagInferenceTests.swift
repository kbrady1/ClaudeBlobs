import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("TagInference")
struct TagInferenceTests {
    let tags = AgentTag.presets

    @Test func promptListsEveryTagWithDescription() {
        let prompt = TagInference.buildPrompt(tags: tags, cwd: "/tmp/proj", firstPrompt: "Review PR 12")
        for tag in tags {
            #expect(prompt.contains("- \(tag.id): \(tag.description)"))
        }
        #expect(prompt.contains("Working directory: /tmp/proj"))
        #expect(prompt.contains("Review PR 12"))
        #expect(prompt.contains("none"))
    }

    @Test func promptTruncatesLongInput() {
        let long = String(repeating: "x", count: 10_000)
        let prompt = TagInference.buildPrompt(tags: tags, cwd: nil, firstPrompt: long)
        #expect(!prompt.contains("Working directory"))
        #expect(prompt.count < 10_000)
    }

    @Test("parses replies", arguments: [
        ("code-review", "code-review"),
        ("  Code-Review.\n", "code-review"),
        ("\"research\"", "research"),
        ("Eng request", "eng-request"),
        ("The best tag is orchestrator", "orchestrator"),
        ("none", nil),
        ("", nil),
        ("something unrelated", nil),
        ("core-task or side-task", nil),
    ])
    func parse(reply: String, expected: String?) {
        #expect(TagInference.parseResponse(reply, tags: tags) == expected)
    }

    @Test func parseUsesOnlyFirstNonEmptyLine() {
        #expect(TagInference.parseResponse("\n\nresearch\ncode-review", tags: tags) == "research")
    }
}

@Suite("TranscriptReader")
struct TranscriptReaderTests {
    @Test func projectDirectoryNameMatchesClaudeLayout() {
        #expect(TranscriptReader.projectDirectoryName(for: "/Users/me/.config/nvim") == "-Users-me--config-nvim")
        #expect(TranscriptReader.projectDirectoryName(for: "/a/ENG-1-x") == "-a-ENG-1-x")
    }

    @Test func readsFirstRealUserPrompt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("s.jsonl")
        let lines = [
            #"{"type":"summary","summary":"x"}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}"#,
            #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"sidechain"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"second prompt"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.firstUserPrompt(in: url) == "Fix the login bug")
    }

    @Test func arrayContentSkipsNonTextBlocks() {
        let mixed = Data(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"},{"type":"text","text":"Ship it"}]}}"#.utf8)
        #expect(TranscriptReader.userPrompt(fromLine: mixed) == "Ship it")
        let noText = Data(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"#.utf8)
        #expect(TranscriptReader.userPrompt(fromLine: noText) == nil)
        let assistant = Data(#"{"type":"assistant","message":{"role":"assistant","content":"hi"}}"#.utf8)
        #expect(TranscriptReader.userPrompt(fromLine: assistant) == nil)
    }

    @Test func returnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).jsonl")
        #expect(TranscriptReader.firstUserPrompt(in: url) == nil)
    }

    @Test func handlesFinalLineWithoutNewline() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).jsonl")
        try #"{"type":"user","message":{"role":"user","content":"only line"}}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.firstUserPrompt(in: url) == "only line")
    }
}

@Suite("TagInferenceCoordinator")
struct TagInferenceCoordinatorTests {
    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func infersOnceUsingFirstPrompt() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let agentStore = AgentStore(statusDirectory: tmp, enableWatcher: false, isProcessAlive: { _ in true })
        let tagStore = TagStore(fileURL: tmp.appendingPathComponent("tags.json"))

        var prompts: [String] = []
        let coordinator = TagInferenceCoordinator(agentStore: agentStore, tagStore: tagStore) { prompt in
            prompts.append(prompt)
            return "code-review"
        }

        let agent = Agent.fixture(sessionId: "s1", pid: 123, firstPrompt: "Please review PR #9")
        let noPrompt = Agent.fixture(sessionId: "s2", pid: 124, cwd: nil)
        let child = Agent.fixture(sessionId: "kid", pid: 0, parentSessionId: "s1", firstPrompt: "child")

        await MainActor.run { coordinator.scan([agent, noPrompt, child]) }
        try await waitUntil { tagStore.source(of: "code-review", on: "s1") == .inferred }
        await MainActor.run {
            #expect(tagStore.source(of: "code-review", on: "s1") == .inferred)
            #expect(tagStore.assignments(for: "s2").isEmpty)
            #expect(tagStore.assignments(for: "kid").isEmpty)
            #expect(!tagStore.inferenceAttempted.contains("s2"))
            #expect(prompts.count == 1)
            #expect(prompts.first?.contains("Please review PR #9") == true)

            // A second scan does not re-run inference for s1.
            coordinator.scan([agent])
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(prompts.count == 1)
    }

    @Test func recordsFailure() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let agentStore = AgentStore(statusDirectory: tmp, enableWatcher: false, isProcessAlive: { _ in true })
        let tagStore = TagStore(fileURL: tmp.appendingPathComponent("tags.json"))
        let coordinator = TagInferenceCoordinator(agentStore: agentStore, tagStore: tagStore) { _ in
            throw TagInferenceError.timeout
        }
        let agent = Agent.fixture(sessionId: "s1", pid: 123, firstPrompt: "hello")
        await MainActor.run { coordinator.scan([agent]) }
        try await waitUntil { tagStore.inferenceErrors["s1"] != nil }
        await MainActor.run {
            #expect(tagStore.inferenceErrors["s1"] == "Inference timed out")
            #expect(tagStore.inferenceAttempted.contains("s1"))
        }
    }
}
