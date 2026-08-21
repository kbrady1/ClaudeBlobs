import AppKit
import SwiftUI
import Combine

final class BoardViewModel: ObservableObject {
    let store: AgentStore
    let tagStore: TagStore
    let themeConfig: ThemeConfig
    let inference: TagInferenceCoordinator?
    let history: SessionHistoryStore
    let conductor: ConductorStore

    @Published var selectedColumn: BoardColumn = .needsAttention
    @Published var selectedRow: Int = 0
    @Published var tagEditorAgentId: String?
    @Published var snoozePickerAgentId: String?
    @Published var isTagManagerShown = false
    @Published var isHelpShown = false
    @Published var tagEditorIndex: Int = 0
    @Published var collapsedColumns: Set<BoardColumn> = BoardViewModel.loadCollapsedColumns() {
        didSet {
            UserDefaults.standard.set(collapsedColumns.map(\.rawValue).sorted(), forKey: "boardCollapsedColumns")
        }
    }
    @Published var closesAfterDeepLink: Bool = {
        UserDefaults.standard.object(forKey: "boardClosesAfterDeepLink") == nil
            ? true : UserDefaults.standard.bool(forKey: "boardClosesAfterDeepLink")
    }() {
        didSet { UserDefaults.standard.set(closesAfterDeepLink, forKey: "boardClosesAfterDeepLink") }
    }
    @Published var historyRange: HistoryRange = {
        HistoryRange(rawValue: UserDefaults.standard.integer(forKey: "boardHistoryRange")) ?? .month
    }() {
        didSet { UserDefaults.standard.set(historyRange.rawValue, forKey: "boardHistoryRange") }
    }
    @Published var statsWindowHours: Int = {
        let v = UserDefaults.standard.integer(forKey: "boardStatsWindowHours")
        return v == 0 ? 24 : v
    }() {
        didSet { UserDefaults.standard.set(statsWindowHours, forKey: "boardStatsWindowHours") }
    }

    enum BoardMode: String, CaseIterable, Identifiable {
        case board, conductor, stats
        var id: String { rawValue }
        var title: String {
            switch self {
            case .board: return "Board"
            case .conductor: return "Conductor"
            case .stats: return "Stats"
            }
        }
        var number: Int {
            switch self {
            case .board: return 1
            case .conductor: return 2
            case .stats: return 3
            }
        }
    }

    @Published var mode: BoardMode = {
        BoardMode(rawValue: UserDefaults.standard.string(forKey: "boardMode") ?? "") ?? .board
    }() {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "boardMode") }
    }
    @Published var conductorIndex: Int = 0
    /// Nil follows the top of the queue; set so a re-sort never swaps the focused session.
    @Published var conductorPinnedId: String?
    @Published var isInstructionsShown = false
    @Published var conductorDraft: String = ""
    @Published var conductorDraftDirty = false
    /// question index → 1-based option
    @Published var conductorChoices: [Int: Int] = [:]
    @Published var conductorStatus: String?
    @Published var conductorSending = false

    private static func loadCollapsedColumns() -> Set<BoardColumn> {
        guard let raw = UserDefaults.standard.stringArray(forKey: "boardCollapsedColumns") else {
            return [.monitoring]
        }
        return Set(raw.compactMap(BoardColumn.init(rawValue:)))
    }

    func isCollapsed(_ column: BoardColumn) -> Bool { collapsedColumns.contains(column) }

    func toggleCollapsed(_ column: BoardColumn) {
        if collapsedColumns.contains(column) {
            collapsedColumns.remove(column)
        } else {
            collapsedColumns.insert(column)
            if selectedColumn == column { clampSelection(force: true) }
        }
    }

    var expandedColumns: [BoardColumnData] { columns.filter { !collapsedColumns.contains($0.column) } }

    var onOpenAgent: ((Agent) -> Void)?
    var onClose: (() -> Void)?

    init(store: AgentStore, tagStore: TagStore, themeConfig: ThemeConfig, inference: TagInferenceCoordinator?, history: SessionHistoryStore, conductor: ConductorStore) {
        self.store = store
        self.tagStore = tagStore
        self.themeConfig = themeConfig
        self.inference = inference
        self.history = history
        self.conductor = conductor
    }

    var focusedConductorItem: ConductorItem? {
        let queue = conductor.queue
        if let pinned = conductorPinnedId, let item = queue.first(where: { $0.id == pinned }) { return item }
        guard conductorIndex >= 0, conductorIndex < queue.count else { return queue.first }
        return queue[conductorIndex]
    }

    func focusConductor(_ item: ConductorItem) {
        conductorIndex = conductor.queue.firstIndex { $0.id == item.id } ?? 0
        conductorPinnedId = item.id
        loadConductorProposal(item)
    }

    func moveConductorFocus(by delta: Int) {
        let queue = conductor.queue
        guard !queue.isEmpty else { return }
        let current = focusedConductorItem.flatMap { item in queue.firstIndex { $0.id == item.id } } ?? 0
        let next = min(max(0, current + delta), queue.count - 1)
        focusConductor(queue[next])
    }

    private func loadConductorProposal(_ item: ConductorItem) {
        conductorDraft = item.assessment?.action.text ?? ""
        conductorDraftDirty = false
        conductorChoices = [:]
        if let option = item.assessment?.action.option, item.assessment?.action.kind == .choose {
            conductorChoices[0] = option
        }
    }

    /// Unpinned focus follows the top of the queue, but never mid-edit.
    func syncConductorFocus() {
        let queue = conductor.queue
        if queue.isEmpty {
            conductorIndex = 0; conductorPinnedId = nil; conductorDraft = ""; conductorDraftDirty = false; conductorChoices = [:]
            return
        }
        if let pinned = conductorPinnedId {
            if let index = queue.firstIndex(where: { $0.id == pinned }) {
                conductorIndex = index
                reloadProposalIfStale(queue[index])
                return
            }
            conductorPinnedId = nil
        }
        conductorIndex = 0
        reloadProposalIfStale(queue[0])
    }

    private func reloadProposalIfStale(_ item: ConductorItem) {
        guard !conductorDraftDirty else { return }
        let proposedText = item.assessment?.action.text ?? ""
        let proposedOption = item.assessment?.action.kind == .choose ? item.assessment?.action.option : nil
        if conductorDraft != proposedText || conductorChoices[0] != proposedOption {
            loadConductorProposal(item)
        }
    }

    func markConductorDraftEdited() {
        guard let item = focusedConductorItem else { return }
        if conductorDraft != (item.assessment?.action.text ?? "") {
            conductorDraftDirty = true
            conductorPinnedId = item.id
        }
    }

    func chooseConductorOption(question: Int, option: Int) {
        guard let item = focusedConductorItem else { return }
        conductorPinnedId = item.id
        conductorDraftDirty = true
        if conductorChoices[question] == option {
            conductorChoices.removeValue(forKey: question)
        } else {
            conductorChoices[question] = option
        }
    }

    func conductorOpen() {
        guard let item = focusedConductorItem else { return }
        open(item.card)
    }

    private func releaseConductorFocus() {
        conductorPinnedId = nil
        conductorDraft = ""
        conductorDraftDirty = false
        conductorChoices = [:]
        conductorIndex = 0
        syncConductorFocus()
    }

    func conductorSkip() {
        guard let item = focusedConductorItem else { return }
        conductor.skip(sessionId: item.agent.sessionId)
        releaseConductorFocus()
    }

    func conductorSnooze(_ duration: SnoozeDuration = .oneHour) {
        guard let item = focusedConductorItem, let agent = agent(id: item.card.id) else { return }
        store.snooze(agent, for: duration)
        releaseConductorFocus()
    }

    var conductorCanSend: Bool {
        guard let item = focusedConductorItem, SessionMessenger.canMessage(item.agent) else { return false }
        if !conductorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !conductorChoices.isEmpty { return true }
        return item.assessment?.action.kind == .approve
    }

    func conductorSend() {
        guard let item = focusedConductorItem, let agent = agent(id: item.card.id) else { return }
        let kind = item.assessment?.action.kind ?? .open
        let text = conductorDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let questions = agent.pendingQuestions ?? []
        let choices = questions.indices.compactMap { conductorChoices[$0] }
        guard !conductorSending else { return }
        if !questions.isEmpty, !conductorChoices.isEmpty || !text.isEmpty {
            let answered = questions.indices.prefix { conductorChoices[$0] != nil }.count
            let covered = text.isEmpty ? answered : answered + 1
            guard choices.count == answered, covered >= questions.count else {
                conductorStatus = "Choose an option for every question"
                return
            }
        }
        if kind == .approve, text.isEmpty, questions.isEmpty, agent.isPlanApproval {
            conductorStatus = "Plan approvals need a look — open the session"
            return
        }
        conductorSending = true
        conductorStatus = "Sending…"
        Task { @MainActor in
            defer { conductorSending = false }
            let result: Result<Void, Error>
            if !questions.isEmpty && (!choices.isEmpty || !text.isEmpty) {
                // Free text goes through the last question's "Type something" option when it has one.
                let freeTextOption = text.isEmpty ? nil : questions.last?.freeTextOptionIndex.map { $0 + 1 }
                result = await SessionMessenger.answer(choices: choices, freeText: text.isEmpty ? nil : text, freeTextOption: freeTextOption, to: agent)
            } else if kind == .approve && text.isEmpty {
                // The proposal was scored on a snapshot; never approve a prompt the model did not see.
                guard agent.status == .permission,
                      agent.lastToolUse == item.agent.lastToolUse,
                      agent.statusChangedAt == item.agent.statusChangedAt else {
                    conductorStatus = "Session changed since it was assessed — review before approving"
                    conductorSending = false
                    return
                }
                result = await SessionMessenger.approve(agent)
            } else {
                guard !text.isEmpty else { conductorStatus = "Nothing to send"; conductorSending = false; return }
                result = await SessionMessenger.send(text: text, to: agent)
            }
            switch result {
            case .success:
                conductorStatus = "Sent to \(store.displayName(for: agent))"
                conductor.skip(sessionId: agent.sessionId)
                releaseConductorFocus()
            case .failure(let error):
                conductorStatus = "Send failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Derived data

    var columns: [BoardColumnData] {
        BoardModel.build(
            agents: store.topLevelAgents,
            children: { [store] id in store.children(of: id) },
            snoozedIds: store.snoozedSessionIds,
            snoozedAt: store.snoozedAt,
            snoozeUntil: store.snoozeUntil,
            cronSessionIds: store.cronSessionIds,
            dismissedClockIds: store.dismissedClockIds,
            passesFilter: { [tagStore] agent in tagStore.matchesFilter(sessionId: agent.sessionId) }
        )
    }

    func cards(in column: BoardColumn) -> [BoardCard] {
        columns.first { $0.column == column }?.cards ?? []
    }

    var selectedCard: BoardCard? { selectedCard(in: columns) }

    /// Same as `selectedCard`, against an already-built board.
    func selectedCard(in columns: [BoardColumnData]) -> BoardCard? {
        let list = columns.first { $0.column == selectedColumn }?.cards ?? []
        guard selectedRow >= 0, selectedRow < list.count else { return nil }
        return list[selectedRow]
    }

    func isSelected(_ card: BoardCard) -> Bool {
        selectedCard?.id == card.id
    }

    /// Live agent for an id (cards hold snapshots; actions want fresh state).
    func agent(id: String) -> Agent? {
        store.agents.first { $0.id == id }
    }

    // MARK: - Selection

    func resetSelection() {
        let all = expandedColumns
        if let first = all.first(where: { !$0.cards.isEmpty }) {
            selectedColumn = first.column
        } else {
            selectedColumn = .needsAttention
        }
        selectedRow = 0
    }

    func clampSelection(force: Bool = false) {
        let count = cards(in: selectedColumn).count
        if count == 0 || force || collapsedColumns.contains(selectedColumn) {
            if let other = expandedColumns.first(where: { !$0.cards.isEmpty }) {
                selectedColumn = other.column
                selectedRow = 0
            } else {
                selectedRow = 0
            }
        } else if selectedRow >= count {
            selectedRow = count - 1
        }
    }

    func select(_ card: BoardCard) {
        selectedColumn = card.column
        selectedRow = cards(in: card.column).firstIndex { $0.id == card.id } ?? 0
    }

    func moveRow(by delta: Int) {
        let count = cards(in: selectedColumn).count
        guard count > 0 else { return }
        selectedRow = min(max(0, selectedRow + delta), count - 1)
    }

    func moveColumn(by direction: Int) {
        let order = BoardColumn.allCases
        guard let current = order.firstIndex(of: selectedColumn) else { return }
        let all = expandedColumns
        for step in 1..<order.count {
            let index = (current + direction * step + order.count * step) % order.count
            let column = order[index]
            if let data = all.first(where: { $0.column == column }), !data.cards.isEmpty {
                selectedColumn = column
                selectedRow = min(selectedRow, data.cards.count - 1)
                return
            }
        }
    }

    // MARK: - Actions

    func open(_ card: BoardCard) {
        let agent = agent(id: card.id) ?? card.agent
        DebugLog.shared.log("Board open agent: \(agent.sessionId)")
        onOpenAgent?(agent)
    }

    func openSelected() {
        guard let card = selectedCard else { return }
        open(card)
    }

    func toggleTagEditor(for card: BoardCard) {
        snoozePickerAgentId = nil
        if tagEditorAgentId == card.id {
            tagEditorAgentId = nil
            return
        }
        // Start on the first inferred tag so Enter confirms it; otherwise the first tag.
        let tags = tagStore.tags
        let inferredIndex = tags.firstIndex { tagStore.source(of: $0.id, on: card.agent.sessionId) == .inferred }
        tagEditorIndex = inferredIndex ?? 0
        tagEditorAgentId = card.id
    }

    func toggleSnoozePicker(for card: BoardCard) {
        tagEditorAgentId = nil
        snoozePickerAgentId = snoozePickerAgentId == card.id ? nil : card.id
    }

    func snooze(_ card: BoardCard, for duration: SnoozeDuration) {
        guard let agent = agent(id: card.id) else { return }
        store.snooze(agent, for: duration)
        snoozePickerAgentId = nil
    }

    func unsnooze(_ card: BoardCard) {
        guard let agent = agent(id: card.id) else { return }
        store.unsnooze(agent)
    }

    func dismiss(_ card: BoardCard) {
        guard let agent = agent(id: card.id) else { return }
        store.dismiss(agent)
    }

    func toggleTag(_ tagId: String, on card: BoardCard) {
        tagStore.toggleTag(tagId, on: card.agent.sessionId)
    }

    func confirmInferredTags(on card: BoardCard) {
        for (tag, source) in tagStore.resolvedTags(for: card.agent.sessionId) where source == .inferred {
            tagStore.confirmTag(tag.id, on: card.agent.sessionId)
        }
    }

    func reinfer(_ card: BoardCard) {
        guard let agent = agent(id: card.id) else { return }
        inference?.infer(agent, force: true)
    }

    func toggleFilter(at index: Int) {
        let tags = tagStore.tags
        guard index >= 0, index < tags.count else { return }
        tagStore.toggleFilter(tagId: tags[index].id)
        clampSelection()
    }

    func closeOverlays() {
        tagEditorAgentId = nil
        snoozePickerAgentId = nil
        isTagManagerShown = false
        isHelpShown = false
        isInstructionsShown = false
    }

    // MARK: - Keyboard

    private enum Key {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    @discardableResult
    func handleKey(_ event: NSEvent, isEditingText: Bool) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        let plain = mods.isEmpty
        let chars = event.charactersIgnoringModifiers ?? ""

        // Before the `isEditingText` guard so these work while a text field has focus.
        if mods == [.command], let digit = chars.first, let number = Int(String(digit)),
           let target = BoardMode.allCases.first(where: { $0.number == number }) {
            mode = target
            return true
        }
        if mode == .conductor {
            if event.keyCode == Key.returnKey, mods.contains(.command) {
                conductorSend()
                return true
            }
            if mods == [.option], let digit = chars.first, let number = Int(String(digit)), number >= 1,
               let first = focusedConductorItem?.agent.pendingQuestions?.first, number <= first.options.count {
                conductorChoices[0] = number
                if let item = focusedConductorItem { conductorPinnedId = item.id }
                conductorSend()
                return true
            }
        }
        if isEditingText {
            return false
        }

        if isHelpShown {
            if event.keyCode == Key.escape || chars == "?" { isHelpShown = false }
            return true
        }
        if mode == .stats {
            if event.keyCode == Key.escape { mode = .board; return true }
            guard plain else { return false }
            switch chars {
            case "1": statsWindowHours = 24
            case "2": statsWindowHours = 168
            case "3": historyRange = .week
            case "4": historyRange = .month
            case "5": historyRange = .quarter
            case "b": mode = .board
            case "d": mode = .conductor
            case "?": isHelpShown = true
            default: return false
            }
            return true
        }
        if mode == .conductor {
            switch event.keyCode {
            case Key.escape: mode = .board; return true
            case Key.returnKey:
                if mods.contains(.command) { conductorSend() } else { conductorOpen() }
                return true
            case Key.up: moveConductorFocus(by: -1); return true
            case Key.down: moveConductorFocus(by: 1); return true
            default: break
            }
            if plain, let digit = chars.first, let number = Int(String(digit)), number >= 1,
               let questions = focusedConductorItem?.agent.pendingQuestions, let first = questions.first,
               number <= first.options.count {
                chooseConductorOption(question: 0, option: number)
                return true
            }
            switch chars {
            case "k": moveConductorFocus(by: -1)
            case "j": moveConductorFocus(by: 1)
            case "s": conductorSkip()
            case "z": conductorSnooze()
            case "i": isInstructionsShown = true
            case "r": conductor.reassessAll()
            case "b": mode = .board
            case "y": mode = .stats
            case "?": isHelpShown = true
            default: return false
            }
            return true
        }
        if isTagManagerShown {
            if event.keyCode == Key.escape { isTagManagerShown = false; return true }
            return false
        }
        if let id = snoozePickerAgentId {
            if event.keyCode == Key.escape { snoozePickerAgentId = nil; return true }
            if let digit = chars.first, let num = Int(String(digit)),
               num >= 1, num <= SnoozeDuration.allCases.count,
               let card = card(id: id) {
                snooze(card, for: SnoozeDuration.allCases[num - 1])
            }
            return true
        }
        if let id = tagEditorAgentId {
            if event.keyCode == Key.escape { tagEditorAgentId = nil; return true }
            guard let card = card(id: id) else { tagEditorAgentId = nil; return true }
            if let digit = chars.first, let num = Int(String(digit)), num >= 1, num <= tagStore.tags.count {
                toggleTag(tagStore.tags[num - 1].id, on: card)
                return true
            }
            let tagCount = tagStore.tags.count
            switch event.keyCode {
            case Key.up: tagEditorIndex = max(0, tagEditorIndex - 1); return true
            case Key.down: tagEditorIndex = min(tagCount - 1, tagEditorIndex + 1); return true
            case Key.returnKey:
                if tagEditorIndex < tagCount { toggleTag(tagStore.tags[tagEditorIndex].id, on: card) }
                return true
            default: break
            }
            switch chars.lowercased() {
            case "k": tagEditorIndex = max(0, tagEditorIndex - 1)
            case "j": tagEditorIndex = min(tagCount - 1, tagEditorIndex + 1)
            case " ": if tagEditorIndex < tagCount { toggleTag(tagStore.tags[tagEditorIndex].id, on: card) }
            case "r": reinfer(card)
            case "c":
                confirmInferredTags(on: card)
                tagEditorAgentId = nil
            case "m": tagEditorAgentId = nil; isTagManagerShown = true
            default: break
            }
            return true
        }

        switch event.keyCode {
        case Key.escape:
            onClose?()
            return true
        case Key.returnKey:
            openSelected()
            return true
        case Key.tab:
            moveColumn(by: mods.contains(.shift) ? -1 : 1)
            return true
        case Key.left: moveColumn(by: -1); return true
        case Key.right: moveColumn(by: 1); return true
        case Key.up: moveRow(by: -1); return true
        case Key.down: moveRow(by: 1); return true
        case Key.delete:
            if let card = selectedCard {
                if card.column == .snoozed { dismiss(card) } else { toggleSnoozePicker(for: card) }
            }
            return true
        default:
            break
        }

        guard plain || mods == [.shift] else { return false }
        switch chars {
        case "h": moveColumn(by: -1)
        case "l": moveColumn(by: 1)
        case "k": moveRow(by: -1)
        case "j": moveRow(by: 1)
        case "t":
            if let card = selectedCard { toggleTagEditor(for: card) }
        case "s":
            if let card = selectedCard {
                if card.column == .snoozed { unsnooze(card) } else { toggleSnoozePicker(for: card) }
            }
        case "u":
            if let card = selectedCard, card.column == .snoozed { unsnooze(card) }
        case "m":
            isTagManagerShown = true
        case "c":
            toggleCollapsed(selectedColumn)
        case "y":
            mode = .stats
        case "d":
            mode = .conductor
        case "n":
            tagStore.toggleUntaggedFilter()
            clampSelection()
        case "0":
            tagStore.clearFilter()
            clampSelection()
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            toggleFilter(at: Int(chars)! - 1)
        case "?":
            isHelpShown = true
        default:
            return false
        }
        return true
    }

    private func card(id: String) -> BoardCard? {
        for column in columns {
            if let card = column.cards.first(where: { $0.id == id }) { return card }
        }
        return nil
    }
}
