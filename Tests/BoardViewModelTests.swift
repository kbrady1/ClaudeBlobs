import Testing
import Foundation
import AppKit
@testable import ClaudeBlobsLib

@Suite("BoardViewModel keys")
struct BoardViewModelTests {
    private func makeModel() -> (BoardViewModel, ConductorStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AgentStore(statusDirectory: dir, enableWatcher: false, isProcessAlive: { _ in true })
        let conductor = ConductorStore(fileURL: dir.appendingPathComponent("conductor.json"), settleSeconds: 0) { _ in "{}" }
        conductor.aiEnabled = false
        let vm = BoardViewModel(
            store: store,
            tagStore: TagStore(fileURL: dir.appendingPathComponent("tags.json")),
            themeConfig: ThemeConfig(),
            inference: nil,
            history: SessionHistoryStore(fileURL: dir.appendingPathComponent("history.json")),
            conductor: conductor
        )
        vm.mode = .board
        return (vm, conductor)
    }

    private func key(_ chars: String, code: UInt16 = 0, mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
            characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
        )!
    }

    private func card(_ id: String, enteredAt: Date = Date()) -> BoardCard {
        let agent = Agent.fixture(sessionId: id, pid: 1, status: .permission, pendingQuestions: [
            AskQuestion(question: "Go?", options: [.init(label: "Yes", description: nil), .init(label: "No", description: nil)]),
        ])
        return BoardCard(agent: agent, column: .needsAttention, effectiveStatus: .permission, enteredAt: enteredAt, children: [], isClockBearing: false, snoozeUntil: nil)
    }

    @Test func commandDigitsSwitchModesEvenWhileEditing() {
        let (vm, _) = makeModel()
        #expect(vm.handleKey(key("2", mods: [.command]), isEditingText: true))
        #expect(vm.mode == .conductor)
        #expect(vm.handleKey(key("3", mods: [.command]), isEditingText: false))
        #expect(vm.mode == .stats)
        #expect(vm.handleKey(key("1", mods: [.command]), isEditingText: true))
        #expect(vm.mode == .board)
        // ⌘4 has no mode and is not consumed.
        #expect(!vm.handleKey(key("4", mods: [.command]), isEditingText: true))
    }

    @Test func escapeSemanticsPerMode() {
        let (vm, _) = makeModel()
        var closed = false
        vm.onClose = { closed = true }
        let esc = key("\u{1B}", code: 53)

        vm.mode = .stats
        #expect(vm.handleKey(esc, isEditingText: false))
        #expect(vm.mode == .board && !closed)

        vm.mode = .conductor
        #expect(vm.handleKey(esc, isEditingText: false))
        #expect(vm.mode == .board && !closed)

        #expect(vm.handleKey(esc, isEditingText: false))
        #expect(closed)
    }

    @Test func optionDigitIsIgnoredWithoutMatchingQuestionOption() {
        let (vm, conductor) = makeModel()
        vm.mode = .conductor
        conductor.refresh(cards: [card("a")], tagsFor: { _ in [] })
        // Option 3 does not exist (two options) → not consumed while editing, nothing sent.
        #expect(!vm.handleKey(key("3", mods: [.option]), isEditingText: true))
        #expect(vm.conductorChoices.isEmpty)
        #expect(!vm.conductorSending)
        // Plain digit (not editing) chooses without sending.
        #expect(vm.handleKey(key("2"), isEditingText: false))
        #expect(vm.conductorChoices[0] == 2)
        #expect(vm.conductorPinnedId == "claude-code:a")
    }

    @Test func pinnedFocusSurvivesQueueReorder() {
        let (vm, conductor) = makeModel()
        vm.mode = .conductor
        let now = Date()
        let old = card("old", enteredAt: now.addingTimeInterval(-10 * 86400))
        let fresh = card("fresh", enteredAt: now)
        conductor.refresh(cards: [old, fresh], tagsFor: { _ in [] })
        vm.syncConductorFocus()
        #expect(vm.focusedConductorItem?.agent.sessionId == "old")
        #expect(vm.conductorPinnedId == nil)

        vm.moveConductorFocus(by: 1)
        #expect(vm.conductorPinnedId == "claude-code:fresh")

        // "fresh" becomes the oldest waiter and moves to the top; focus stays on it at its new index.
        let fresh2 = card("fresh", enteredAt: now.addingTimeInterval(-20 * 86400))
        conductor.refresh(cards: [old, fresh2], tagsFor: { _ in [] })
        vm.syncConductorFocus()
        #expect(conductor.queue.map(\.agent.sessionId) == ["fresh", "old"])
        #expect(vm.focusedConductorItem?.agent.sessionId == "fresh")
        #expect(vm.conductorIndex == 0)

        // Pinned session leaves the queue → focus falls back to the top, unpinned.
        conductor.refresh(cards: [old], tagsFor: { _ in [] })
        vm.syncConductorFocus()
        #expect(vm.conductorPinnedId == nil)
        #expect(vm.focusedConductorItem?.agent.sessionId == "old")
    }

    @Test func dirtyDraftPinsAndBlocksProposalReload() {
        let (vm, conductor) = makeModel()
        vm.mode = .conductor
        conductor.refresh(cards: [card("a")], tagsFor: { _ in [] })
        vm.syncConductorFocus()
        vm.conductorDraft = "my own answer"
        vm.markConductorDraftEdited()
        #expect(vm.conductorDraftDirty)
        #expect(vm.conductorPinnedId == "claude-code:a")
        vm.syncConductorFocus()
        #expect(vm.conductorDraft == "my own answer")
        vm.conductorSkip()
        #expect(vm.conductorPinnedId == nil)
        #expect(vm.conductorDraft == "")
        #expect(conductor.queue.first?.isSkipped == true)
    }

    @Test func helpOverlayClosesInEveryMode() {
        let (vm, _) = makeModel()
        let esc = key("\u{1B}", code: 53)
        for mode in [BoardViewModel.BoardMode.conductor, .stats] {
            vm.mode = mode
            #expect(vm.handleKey(key("?"), isEditingText: false))
            #expect(vm.isHelpShown)
            #expect(vm.handleKey(esc, isEditingText: false))
            #expect(!vm.isHelpShown)
            #expect(vm.mode == mode)
        }
    }

    @Test func modifiedDigitsDoNotFireInStatsOrConductor() {
        let (vm, conductor) = makeModel()
        vm.mode = .stats
        vm.statsWindowHours = 24
        #expect(!vm.handleKey(key("2", mods: [.control]), isEditingText: false))
        #expect(vm.statsWindowHours == 24)
        vm.mode = .conductor
        conductor.refresh(cards: [card("a")], tagsFor: { _ in [] })
        #expect(!vm.handleKey(key("2", mods: [.control]), isEditingText: false))
        #expect(vm.conductorChoices.isEmpty)
    }

    @Test func chosenOptionSurvivesSync() {
        let (vm, conductor) = makeModel()
        vm.mode = .conductor
        conductor.refresh(cards: [card("a")], tagsFor: { _ in [] })
        vm.syncConductorFocus()
        vm.chooseConductorOption(question: 0, option: 2)
        vm.syncConductorFocus()
        #expect(vm.conductorChoices[0] == 2)
    }

    @Test func proposalLoadsWhenAssessmentArrivesWithoutReorder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AgentStore(statusDirectory: dir, enableWatcher: false, isProcessAlive: { _ in true })
        let conductor = ConductorStore(fileURL: dir.appendingPathComponent("conductor.json"), settleSeconds: 0) { _ in
            #"{"score": 90, "reason": "obvious", "action": {"kind": "choose", "option": 2}}"#
        }
        let vm = BoardViewModel(
            store: store, tagStore: TagStore(fileURL: dir.appendingPathComponent("tags.json")), themeConfig: ThemeConfig(),
            inference: nil, history: SessionHistoryStore(fileURL: dir.appendingPathComponent("history.json")), conductor: conductor
        )
        vm.mode = .conductor
        await MainActor.run { conductor.refresh(cards: [card("a")], tagsFor: { _ in [] }) }
        vm.syncConductorFocus()
        #expect(vm.conductorChoices.isEmpty)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, await MainActor.run(body: { conductor.queue.first?.assessment == nil }) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await MainActor.run { vm.syncConductorFocus() }
        #expect(vm.conductorChoices[0] == 2)
    }
}
