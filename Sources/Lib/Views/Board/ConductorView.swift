import SwiftUI

struct ConductorView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject var conductor: ConductorStore
    @ObservedObject var tagStore: TagStore
    @ObservedObject var store: AgentStore
    let theme: ColorTheme

    var body: some View {
        let queue = conductor.queue
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Conductor")
                    .font(.system(size: 15, weight: .semibold))
                Text(summary(queue))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !conductor.assessing.isEmpty {
                    ProgressView().controlSize(.mini)
                    Text("analyzing \(conductor.assessing.count)…")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let status = viewModel.conductorStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(status.hasPrefix("Send failed") ? .orange : .secondary)
                        .lineLimit(1)
                }
                pillButton("Re-analyze", symbol: "arrow.clockwise", key: "R", help: "Drop cached scores and re-score every session") {
                    conductor.reassessAll()
                }
                pillButton("Instructions…", symbol: "text.alignleft", key: "I", help: "How the Conductor decides what comes next") {
                    viewModel.isInstructionsShown = true
                }
            }

            if queue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28))
                        .foregroundColor(ChartStyle.green)
                    Text("Nothing is waiting on you.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Sessions in Needs Attention and Idle show up here, ranked.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // GeometryReader bounds the hero; without it the session ScrollView
                // grows without limit and pushes the actions and queue off screen.
                GeometryReader { geo in
                VStack(alignment: .leading, spacing: 10) {
                    if let focused = viewModel.focusedConductorItem {
                        ConductorHeroCard(
                            item: focused,
                            tags: tagStore.resolvedTags(for: focused.agent.sessionId).map(\.tag),
                            displayName: store.displayName(for: focused.agent),
                            hostAppIcon: store.hostAppIcons[focused.agent.pid],
                            theme: theme,
                            draft: $viewModel.conductorDraft,
                            choices: viewModel.conductorChoices,
                            canSend: viewModel.conductorCanSend,
                            isSending: viewModel.conductorSending,
                            onDraftEdited: { viewModel.markConductorDraftEdited() },
                            onChoose: { viewModel.chooseConductorOption(question: $0, option: $1) },
                            onOpen: { viewModel.conductorOpen() },
                            onSkip: { viewModel.conductorSkip() },
                            onUnskip: { conductor.unskip(sessionId: focused.agent.sessionId) },
                            onSnooze: { viewModel.conductorSnooze($0) },
                            onSend: { viewModel.conductorSend() }
                        )
                        .frame(height: max(240, geo.size.height - 150))
                    }

                    Spacer(minLength: 28)

                    HStack(spacing: 8) {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                        Text("\(queue.count) in queue")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("↑ ↓ to move")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(queue.enumerated()), id: \.element.id) { index, item in
                                    ConductorQueueCard(
                                        index: index + 1,
                                        item: item,
                                        tags: tagStore.resolvedTags(for: item.agent.sessionId).map(\.tag),
                                        displayName: store.displayName(for: item.agent),
                                        theme: theme,
                                        isFocused: viewModel.focusedConductorItem?.id == item.id
                                    )
                                    .id(item.id)
                                    .onTapGesture { viewModel.focusConductor(item) }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onChange(of: viewModel.conductorIndex) { _ in
                            if let id = viewModel.focusedConductorItem?.id {
                                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                    }
                }
                }
            }
        }
        .onChange(of: queue.map { "\($0.id):\($0.assessment?.fingerprint ?? "")" }) { _ in viewModel.syncConductorFocus() }
        .onAppear { viewModel.syncConductorFocus() }
    }

    private func summary(_ queue: [ConductorItem]) -> String {
        let attention = queue.filter { $0.card.column == .needsAttention }.count
        let idle = queue.count - attention
        var parts: [String] = []
        if attention > 0 { parts.append("\(attention) need attention") }
        if idle > 0 { parts.append("\(idle) idle") }
        return parts.isEmpty ? "queue empty" : parts.joined(separator: " · ")
    }

    private func pillButton(_ title: String, symbol: String, key: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 11))
                Text(key)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

// MARK: - Hero (the session to work on now)

private struct ConductorHeroCard: View {
    let item: ConductorItem
    let tags: [AgentTag]
    let displayName: String
    let hostAppIcon: NSImage?
    let theme: ColorTheme
    @Binding var draft: String
    let choices: [Int: Int]
    let canSend: Bool
    let isSending: Bool
    let onDraftEdited: () -> Void
    let onChoose: (Int, Int) -> Void
    @State private var isSnoozeShown = false
    let onOpen: () -> Void
    let onSkip: () -> Void
    let onUnskip: () -> Void
    let onSnooze: (SnoozeDuration) -> Void
    let onSend: () -> Void

    private var agent: Agent { item.agent }
    private var action: ConductorAction { item.assessment?.action ?? .open }
    private var canMessage: Bool { SessionMessenger.canMessage(agent) }
    private var accent: Color {
        AgentSpriteView.blobColor(
            status: item.card.effectiveStatus, isDone: agent.isDone, isSnoozed: false,
            isPlanApproval: agent.isPlanApproval, isAskingQuestion: agent.isAskingQuestion,
            staleness: agent.staleness, theme: theme
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            sessionSection
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            conductorSection
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 16) {
            AgentSpriteView(
                status: item.card.effectiveStatus, size: 56, theme: theme,
                isDone: agent.isDone, staleness: agent.staleness,
                isPlanApproval: agent.isPlanApproval, isAskingQuestion: agent.isAskingQuestion,
                isBashPermission: agent.isBashPermission, isFilePermission: agent.isFilePermission,
                isInterrupted: agent.isInterrupted, isToolFailure: agent.isToolFailure, isAPIError: agent.isAPIError,
                useGlassBlob: true, animated: false
            )
            .frame(width: 64, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("NOW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                        .tracking(1)
                    if item.isSkipped {
                        Text("skipped").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    ForEach(tags) { tag in TagChip(tag: tag, source: .confirmed) }
                }
                Text(displayName)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                metaRow
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ScorePill(item: item, large: true)
                Text("priority")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Label(ConductorStore.stateDescription(item.card), systemImage: item.card.column.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(accent)
            dot
            Text("waiting \(BoardModel.formatElapsed(item.waitSeconds)) of working hours")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if let cwd = agent.cwd, let repo = RepoInfo.resolve(cwd: cwd) {
                dot
                if let hostAppIcon {
                    Image(nsImage: hostAppIcon).resizable().frame(width: 13, height: 13)
                }
                Text(repo.label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Session

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FROM THE SESSION")
            if let tool = agent.lastToolUse, item.card.effectiveStatus == .permission, !agent.isAskingQuestion {
                Text(agent.permissionToolUseExpanded.isEmpty ? tool : agent.permissionToolUseExpanded)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(accent)
                    .lineLimit(5)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.1)))
            }
            ScrollView {
                MarkdownMessageView(text: sessionText, fontSize: 14)
                    .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Conductor

    private var hasQuestions: Bool { !(agent.pendingQuestions ?? []).isEmpty }

    private var conductorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONDUCTOR")
            reasoning
            questionsList
            replyEditor
            actionRow
        }
    }

    @ViewBuilder
    private var reasoning: some View {
        if item.isAssessing {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Analyzing…").font(.system(size: 12)).foregroundColor(.secondary) }
        } else if let assessment = item.assessment {
            Text(assessment.reason.isEmpty ? "No reasoning returned." : assessment.reason)
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if let error = item.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundColor(.orange)
        } else {
            Text("Not analyzed yet.").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var questionsList: some View {
        if let questions = agent.pendingQuestions, !questions.isEmpty {
            ForEach(Array(questions.enumerated()), id: \.offset) { qi, question in
                QuestionOptionsView(
                    index: qi,
                    question: question,
                    chosen: choices[qi],
                    proposed: qi == 0 && action.kind == .choose ? action.option : nil,
                    accent: accent,
                    onChoose: { onChoose(qi, $0) }
                )
            }
        }
    }

    @ViewBuilder
    private var replyEditor: some View {
        if canMessage || action.kind == .reply {
            if action.kind == .approve && draft.isEmpty && !hasQuestions {
                sectionLabel("PROPOSED: APPROVE")
                Text("Send \"1\" to accept the pending permission.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                sectionLabel(hasQuestions ? (choices.isEmpty ? "OR TYPE A REPLY INSTEAD" : "TEXT FOR THE REMAINING QUESTIONS") : (action.kind == .reply ? "PROPOSED REPLY" : "REPLY"))
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: hasQuestions ? 56 : 90, maxHeight: 140)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.45), lineWidth: 1.5))
                    .disabled(isSending)
                    .onChange(of: draft) { _ in onDraftEdited() }
            }
            if !canMessage {
                Text("No superset / cmux channel for this session — open it to reply.")
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if canSend || isSending {
                actionButton(isSending ? "Sending…" : sendTitle, symbol: "paperplane.fill", key: "⌘↵", prominent: true, busy: isSending, action: onSend)
                    .disabled(isSending)
            }
            actionButton("Open", symbol: "arrow.up.right.square", key: "↵", prominent: !canSend && !isSending, action: onOpen)
            if item.isSkipped {
                actionButton("Unskip", symbol: "arrow.uturn.backward", key: nil, action: onUnskip)
            } else {
                actionButton("Skip", symbol: "forward.fill", key: "S", action: onSkip)
            }
            actionButton("Snooze", symbol: "moon.fill", key: "Z") { isSnoozeShown = true }
                .popover(isPresented: $isSnoozeShown, arrowEdge: .bottom) {
                    BoardSnoozePopover { duration in
                        isSnoozeShown = false
                        onSnooze(duration)
                    }
                }
        }
        .padding(.top, 4)
    }

    private var sendTitle: String {
        if !(agent.pendingQuestions ?? []).isEmpty { return choices.isEmpty ? "Send answer" : "Send choice" }
        if action.kind == .approve && draft.isEmpty { return "Approve" }
        return "Send reply"
    }

    private var dot: some View {
        Text("·").foregroundColor(.secondary)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.6)
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.14)))
    }

    private var sessionText: String {
        if let raw = agent.rawLastMessage, !raw.isEmpty { return raw }
        if let message = agent.lastMessage, !message.isEmpty { return message }
        if agent.isAskingQuestion, let tool = agent.lastToolUse, let q = Agent.extractAskQuestion(from: String(tool.dropFirst("AskUserQuestion:".count))) { return q }
        return item.card.effectiveStatus == .permission ? "Waiting for permission." : "No message."
    }

    private func actionButton(_ title: String, symbol: String, key: String?, prominent: Bool = false, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 14, height: 14)
                } else {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: prominent ? .semibold : .medium))
                if let key { keyCap(key) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(prominent ? accent.opacity(0.45) : Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(prominent ? accent : Color.white.opacity(0.18), lineWidth: prominent ? 1.5 : 1))
            .foregroundColor(prominent ? .white : .primary.opacity(0.85))
            .shadow(color: prominent ? accent.opacity(0.35) : .clear, radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - AskUserQuestion options

private struct QuestionOptionsView: View {
    let index: Int
    let question: AskQuestion
    let chosen: Int?
    let proposed: Int?
    let accent: Color
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.2)))
                        .foregroundColor(accent)
                }
                Text(question.question)
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if question.multiSelect == true {
                    Text("multi-select").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            ForEach(Array(question.options.enumerated()), id: \.offset) { oi, option in
                let number = oi + 1
                let isChosen = chosen == number
                Button {
                    onChoose(number)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(isChosen ? .white : .secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(isChosen ? accent : Color.white.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(option.label)
                                    .font(.system(size: 13, weight: isChosen ? .semibold : .regular))
                                if proposed == number {
                                    Text("conductor's pick")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(accent)
                                }
                            }
                            if let description = option.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isChosen ? accent.opacity(0.18) : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isChosen ? accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(index == 0 ? "Press \(number) to choose" : "Click to choose")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Queue cards (horizontal strip)

private struct ConductorQueueCard: View {
    let index: Int
    let item: ConductorItem
    let tags: [AgentTag]
    let displayName: String
    let theme: ColorTheme
    let isFocused: Bool

    var body: some View {
        let accent = item.card.column.color(theme: theme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(index)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                ScorePill(item: item, large: false)
            }
            HStack(spacing: 4) {
                ForEach(tags.prefix(2)) { tag in TagChip(tag: tag, source: .confirmed) }
                Text(item.isAssessing ? "analyzing…" : (item.assessment?.reason ?? item.error ?? ConductorStore.stateDescription(item.card)))
                    .font(.system(size: 10))
                    .foregroundColor(item.error != nil && item.assessment == nil ? .orange : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isSkipped {
                    Text("skipped").font(.system(size: 9)).foregroundColor(.secondary)
                }
                Text(BoardModel.formatElapsed(item.waitSeconds))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isFocused ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isFocused ? Color.white.opacity(0.7) : accent.opacity(0.25), lineWidth: isFocused ? 1.5 : 1))
        .opacity(item.isSkipped ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

private struct ScorePill: View {
    let item: ConductorItem
    var large: Bool = false

    var body: some View {
        let score = item.assessment?.score
        let color: Color = {
            guard let score else { return ChartStyle.muted }
            if score >= 75 { return ChartStyle.red }
            if score >= 50 { return ChartStyle.orange }
            return ChartStyle.blue
        }()
        Text(score.map(String.init) ?? "–")
            .font(.system(size: large ? 22 : 11, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .frame(width: large ? 64 : 34)
            .padding(.vertical, large ? 6 : 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .help(score == nil ? "Not scored yet" : "Conductor score \(score!)/100 · rank \(String(format: "%.1f", item.rank))")
    }
}

// MARK: - Instructions sheet

struct ConductorInstructionsView: View {
    @ObservedObject var conductor: ConductorStore
    let onDone: () -> Void
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conductor Instructions")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("Use AI scoring", isOn: $conductor.aiEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }
            Text("Tell the Conductor how you want waiting sessions prioritized and when a reply is obvious enough to propose. Changing the instructions re-scores every session.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 220)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1)))
            HStack {
                Button("Reset to default") { text = ConductorStore.defaultInstructions }
                    .controlSize(.small)
                Spacer()
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != conductor.instructions {
                        conductor.instructions = trimmed.isEmpty ? ConductorStore.defaultInstructions : trimmed
                        conductor.reassessAll()
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 600)
        .onAppear { text = conductor.instructions }
    }
}
