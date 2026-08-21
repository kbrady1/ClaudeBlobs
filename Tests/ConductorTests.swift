import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("WorkingHours")
struct WorkingHoursTests {
    // Use a fixed calendar/time zone so the expectations hold everywhere.
    var quiet: WorkingHours {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Denver")!
        return WorkingHours(calendar: cal)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Denver")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func insideOneWorkday() {
        // Wed 2026-08-19 10:00 → 12:30
        #expect(quiet.activeSeconds(from: date(2026, 8, 19, 10), to: date(2026, 8, 19, 12, 30)) == 2.5 * 3600)
    }

    @Test func eveningAndNightAreQuiet() {
        // Wed 16:00 → Thu 10:00 = 1h (16–17) + 1h (9–10)
        #expect(quiet.activeSeconds(from: date(2026, 8, 19, 16), to: date(2026, 8, 20, 10)) == 2 * 3600)
    }

    @Test func weekendIsQuiet() {
        // Fri 2026-08-21 16:00 → Mon 2026-08-24 09:30 = 1h + 0.5h
        #expect(quiet.activeSeconds(from: date(2026, 8, 21, 16), to: date(2026, 8, 24, 9, 30)) == 1.5 * 3600)
        // Entirely inside Saturday
        #expect(quiet.activeSeconds(from: date(2026, 8, 22, 10), to: date(2026, 8, 22, 15)) == 0)
    }

    @Test func beforeOpenAndReversedRanges() {
        #expect(quiet.activeSeconds(from: date(2026, 8, 19, 6), to: date(2026, 8, 19, 8)) == 0)
        #expect(quiet.activeSeconds(from: date(2026, 8, 19, 12), to: date(2026, 8, 19, 10)) == 0)
    }
}

@Suite("ConductorStore")
struct ConductorStoreTests {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("conductor-\(UUID().uuidString)/conductor.json")
    }

    private func card(_ id: String, status: AgentStatus = .permission, waitReason: String? = nil, message: String? = nil, enteredAt: Date = Date()) -> BoardCard {
        let agent = Agent.fixture(sessionId: id, pid: 1, status: status, lastMessage: message, waitReason: waitReason)
        let column = BoardModel.column(for: agent, effectiveStatus: status, isSnoozed: false, isClockBearing: false)
        return BoardCard(agent: agent, column: column, effectiveStatus: status, enteredAt: enteredAt, children: [], isClockBearing: false, snoozeUntil: nil)
    }

    private func waitUntil(timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func parseResponseVariants() {
        let parsed = ConductorStore.parseResponse(#"Sure: {"score": 82, "reason": "Blocks a long run", "action": {"kind": "approve"}} done"#)
        #expect(parsed?.score == 82)
        #expect(parsed?.reason == "Blocks a long run")
        #expect(parsed?.action == ConductorAction(kind: .approve, text: nil))

        let reply = ConductorStore.parseResponse(#"{"score": "40", "reason": "x", "action": {"kind": "reply", "text": "Yes, go ahead."}}"#)
        #expect(reply?.action == ConductorAction(kind: .reply, text: "Yes, go ahead."))

        // reply without text degrades to open; score clamps.
        let bad = ConductorStore.parseResponse(#"{"score": 140, "action": {"kind": "reply"}}"#)
        #expect(bad?.score == 100)
        #expect(bad?.action.kind == .open)

        #expect(ConductorStore.parseResponse("no json here") == nil)

        let choose = ConductorStore.parseResponse(#"{"score": 70, "reason": "pick 1", "action": {"kind": "choose", "option": 1}}"#)
        #expect(choose?.action == ConductorAction(kind: .choose, option: 1))
        let badChoose = ConductorStore.parseResponse(#"{"score": 70, "action": {"kind": "choose"}}"#)
        #expect(badChoose?.action.kind == .open)
    }

    @Test func promptEnumeratesPendingQuestions() {
        let agent = Agent.fixture(sessionId: "q", pid: 1, status: .permission, lastToolUse: "AskUserQuestion: {...}", pendingQuestions: [
            AskQuestion(question: "Stop it now?", header: "Stop leaked sandbox", options: [
                .init(label: "Yes, stop it now (recommended)", description: "POST /stop"),
                .init(label: "No, I'll handle it", description: nil),
                .init(label: "Type something.", description: nil),
            ]),
        ])
        let card = BoardCard(agent: agent, column: .needsAttention, effectiveStatus: .permission, enteredAt: Date(), children: [], isClockBearing: false, snoozeUntil: nil)
        let prompt = ConductorStore.buildPrompt(card: card, tags: [], instructions: "x", waitSeconds: 0, repo: nil)
        #expect(prompt.contains("question 1 [Stop leaked sandbox]: Stop it now?"))
        #expect(prompt.contains("option 1: Yes, stop it now (recommended) — POST /stop"))
        #expect(prompt.contains("option 3: Type something."))
        #expect(agent.pendingQuestions?.first?.freeTextOptionIndex == 2)
    }

    @Test func rankCombinesScoreWaitAndSkip() {
        #expect(ConductorStore.rank(score: 80, waitSeconds: 0, isSkipped: false) == 80)
        #expect(ConductorStore.rank(score: nil, waitSeconds: 1200, isSkipped: false) == 52)
        #expect(ConductorStore.rank(score: 80, waitSeconds: 99_999, isSkipped: false) == 95)
        #expect(ConductorStore.rank(score: 80, waitSeconds: 0, isSkipped: true) == 20)
    }

    @Test func scoresOncePerFingerprintAndReordersLocally() async throws {
        let lock = NSLock()
        var recorded: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
        let store = ConductorStore(fileURL: tmpURL(), settleSeconds: 0) { prompt in
            lock.lock(); recorded.append(prompt); lock.unlock()
            let score = prompt.contains("asking permission") ? 90 : 30
            return #"{"score": \#(score), "reason": "r", "action": {"kind": "open"}}"#
        }
        let a = card("session-a", status: .permission)
        let b = card("session-b", status: .waiting, waitReason: "done")
        await MainActor.run { store.refresh(cards: [b, a], tagsFor: { _ in [] }) }
        try await waitUntil { store.assessments.count == 2 }
        await MainActor.run {
            #expect(calls.count == 2)
            #expect(store.queue.map(\.id) == [a.id, b.id])
        }

        // Same inputs → no new calls, same order.
        await MainActor.run { store.refresh(cards: [a, b], tagsFor: { _ in [] }) }
        try await Task.sleep(nanoseconds: 200_000_000)
        await MainActor.run { #expect(calls.count == 2) }

        // A changed message re-scores only that session.
        let b2 = card("session-b", status: .waiting, waitReason: "question", message: "Which option?")
        await MainActor.run { store.refresh(cards: [a, b2], tagsFor: { _ in [] }) }
        try await waitUntil { store.assessments["session-b"]?.fingerprint == store.fingerprint(for: b2, tags: []) }
        await MainActor.run { #expect(calls.count == 3) }

        // Skip sends it to the back without AI work; the skip lifts when it changes.
        await MainActor.run {
            store.skip(sessionId: "session-a")
            #expect(store.queue.first?.id == b2.id)
            #expect(store.queue.last?.isSkipped == true)
        }
        let a2 = card("session-a", status: .permission, message: "new ask")
        await MainActor.run { store.refresh(cards: [a2, b2], tagsFor: { _ in [] }) }
        try await waitUntil { store.skipped.isEmpty }
        await MainActor.run { #expect(calls.count == 4) }
    }

    @Test func unsettledSessionsWaitBeforeAdmission() async throws {
        var calls = 0
        let store = ConductorStore(fileURL: tmpURL(), settleSeconds: 15) { _ in
            calls += 1
            return #"{"score": 50, "reason": "r", "action": {"kind": "open"}}"#
        }
        let now = Date()
        let fresh = card("fresh", status: .permission, enteredAt: now.addingTimeInterval(-3))
        let settled = card("settled", status: .permission, enteredAt: now.addingTimeInterval(-60))
        await MainActor.run { store.refresh(cards: [fresh, settled], tagsFor: { _ in [] }, now: now) }
        try await waitUntil { store.assessments["settled"] != nil }
        await MainActor.run {
            #expect(store.queue.map(\.id) == [settled.id])
            #expect(calls == 1)
            // Once it has sat long enough it is admitted and scored.
            store.refresh(cards: [fresh, settled], tagsFor: { _ in [] }, now: now.addingTimeInterval(20))
        }
        try await waitUntil { store.assessments["fresh"] != nil }
        await MainActor.run {
            #expect(store.queue.count == 2)
            #expect(calls == 2)
        }
    }

    @Test func instructionsChangeInvalidatesFingerprint() {
        let store = ConductorStore(fileURL: tmpURL()) { _ in "{}" }
        let c = card("s")
        let before = store.fingerprint(for: c, tags: [])
        store.instructions = "Only permissions matter."
        #expect(store.fingerprint(for: c, tags: []) != before)
    }

    @Test func persistsAssessmentsAndInstructions() async throws {
        let url = tmpURL()
        do {
            let store = ConductorStore(fileURL: url, settleSeconds: 0) { _ in #"{"score": 55, "reason": "kept", "action": {"kind": "none"}}"# }
            store.instructions = "Custom rules"
            await MainActor.run { store.refresh(cards: [card("s")], tagsFor: { _ in [] }) }
            try await waitUntil { store.assessments["s"] != nil }
        }
        let reloaded = ConductorStore(fileURL: url) { _ in "{}" }
        #expect(reloaded.instructions == "Custom rules")
        #expect(reloaded.assessments["s"]?.score == 55)
    }

    @Test func promptMentionsInstructionsTagsAndState() {
        let c = card("s", status: .permission)
        let prompt = ConductorStore.buildPrompt(card: c, tags: [AgentTag.presets[0]], instructions: "Permissions first.", waitSeconds: 600, repo: RepoInfo(name: "o/r", branch: "main"))
        #expect(prompt.contains("Permissions first."))
        #expect(prompt.contains("tag: Core task"))
        #expect(prompt.contains("asking permission to run a tool"))
        #expect(prompt.contains("o/r · main"))
        #expect(prompt.contains("10m"))
    }

    @Test func aiDisabledNeverCallsRunnerAndSortsByWait() async throws {
        var calls = 0
        let store = ConductorStore(fileURL: tmpURL(), settleSeconds: 0) { _ in calls += 1; return "{}" }
        store.aiEnabled = false
        // 10 days back always spans several workdays, so the wait boost caps at 15 even outside working hours.
        let old = card("old", status: .permission, enteredAt: Date().addingTimeInterval(-10 * 86400))
        let fresh = card("fresh", status: .permission)
        await MainActor.run { store.refresh(cards: [fresh, old], tagsFor: { _ in [] }) }
        try await Task.sleep(nanoseconds: 200_000_000)
        await MainActor.run {
            #expect(calls == 0)
            #expect(store.queue.map(\.agent.sessionId) == ["old", "fresh"])
            #expect(store.queue.allSatisfy { $0.assessment == nil && !$0.isAssessing })
        }
    }

    @Test func refreshForgetsDepartedSessions() async throws {
        let store = ConductorStore(fileURL: tmpURL(), settleSeconds: 0) { _ in #"{"score": 60, "reason": "r", "action": {"kind": "open"}}"# }
        let a = card("a"), b = card("b")
        await MainActor.run { store.refresh(cards: [a, b], tagsFor: { _ in [] }) }
        try await waitUntil { store.assessments.count == 2 }
        await MainActor.run {
            store.skip(sessionId: "b")
            store.refresh(cards: [a], tagsFor: { _ in [] })
            #expect(store.assessments["b"] == nil)
            #expect(store.skipped["b"] == nil)
            #expect(store.queue.map(\.agent.sessionId) == ["a"])
        }
    }

    @Test func runnerFailureIsRecordedAndQueueStillBuilds() async throws {
        let store = ConductorStore(fileURL: tmpURL(), settleSeconds: 0) { _ in throw TagInferenceError.failed("boom") }
        await MainActor.run { store.refresh(cards: [card("s")], tagsFor: { _ in [] }) }
        try await waitUntil { store.errors["s"] != nil }
        await MainActor.run {
            #expect(store.assessments["s"] == nil)
            #expect(store.assessing.isEmpty)
            #expect(store.queue.count == 1)
            #expect(store.queue.first?.error?.contains("boom") == true)
            #expect(store.queue.first?.rank == ConductorStore.rank(score: nil, waitSeconds: store.queue.first!.waitSeconds, isSkipped: false))
        }
    }

    @Test func persistsSkippedAndAiEnabled() {
        let url = tmpURL()
        do {
            let store = ConductorStore(fileURL: url, settleSeconds: 0) { _ in "{}" }
            store.aiEnabled = false
            store.refresh(cards: [card("s")], tagsFor: { _ in [] })
            store.skip(sessionId: "s")
            #expect(store.skipped["s"] != nil)
        }
        let reloaded = ConductorStore(fileURL: url) { _ in "{}" }
        #expect(reloaded.aiEnabled == false)
        #expect(reloaded.skipped["s"] != nil)
    }

    @Test func answerStepsNavigateWithArrows() {
        typealias S = SessionMessenger.AnswerStep
        #expect(SessionMessenger.answerSteps(choices: [3], freeText: nil, freeTextOption: nil, questionCount: 1) == [S.select(3)])
        #expect(SessionMessenger.answerSteps(choices: [1, 2, 1], freeText: nil, freeTextOption: nil, questionCount: 3)
                == [S.select(1), .select(2), .select(1), .submit])
        #expect(SessionMessenger.answerSteps(choices: [], freeText: "hi", freeTextOption: 3, questionCount: 1)
                == [S.select(3), .text("hi")])
        #expect(SessionMessenger.answerSteps(choices: [], freeText: nil, freeTextOption: nil, questionCount: 2).isEmpty)
    }

    @Test func shellQuoting() {
        #expect(SessionMessenger.shellQuote("it's ok") == "'it'\\''s ok'")
    }
}

@Suite("SessionMessenger")
struct SessionMessengerTests {
    @Test func channelPrecedence() {
        let both = Agent.fixture(cmuxWorkspace: "ws", cmuxSurface: "surf", supersetWorkspace: "sws", supersetTerminal: "t1")
        #expect(SessionMessenger.channel(for: both) == .superset)
        // Superset without a terminal id cannot be addressed; cmux wins.
        let noTerminal = Agent.fixture(cmuxWorkspace: "ws", cmuxSurface: "surf", supersetWorkspace: "sws")
        #expect(SessionMessenger.channel(for: noTerminal) == .cmux)
        let supersetOnly = Agent.fixture(supersetWorkspace: "sws")
        #expect(SessionMessenger.channel(for: supersetOnly) == nil)
        #expect(!SessionMessenger.canMessage(supersetOnly))
        #expect(SessionMessenger.channel(for: Agent.fixture()) == nil)
    }

    @Test func sendWithoutChannelFails() async {
        let result = await SessionMessenger.send(text: "hi", to: Agent.fixture())
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect((error as? MessengerError) == nil || error.localizedDescription.contains("no superset or cmux"))
    }

    @Test func answerWithNothingToSendFails() async {
        let result = await SessionMessenger.answer(choices: [], freeText: "", freeTextOption: nil, questionCount: 1, to: Agent.fixture())
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error.localizedDescription == "Nothing to send")
    }
}

@Suite("MarkdownMessageView")
struct MarkdownBlocksTests {
    @Test func splitsBlocks() {
        let text = """
        These confirm it exactly:

        - Reservation 1: **Processed** ✓
        - Reservation 2: done
        1. first
        > quoted line
        > continues
        ```
        let x = 1
        ```
        ## Heading
        Tail paragraph
        spans two lines.
        """
        let blocks = MarkdownMessageView.blocks(from: text)
        #expect(blocks == [
            .paragraph("These confirm it exactly:"),
            .bullet("Reservation 1: **Processed** ✓"),
            .bullet("Reservation 2: done"),
            .numbered("1", "first"),
            .quote("quoted line continues"),
            .code("let x = 1"),
            .heading("Heading"),
            .paragraph("Tail paragraph spans two lines."),
        ])
    }
}
