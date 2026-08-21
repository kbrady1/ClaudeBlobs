import SwiftUI

struct BoardView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject var store: AgentStore
    @ObservedObject var tagStore: TagStore
    @ObservedObject var themeConfig: ThemeConfig

    var body: some View {
        let columns = viewModel.columns
        let selectedCardId = viewModel.selectedCard(in: columns)?.id
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.10), Color(white: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if viewModel.mode == .conductor, let focused = viewModel.focusedConductorItem {
                let accent = AgentSpriteView.blobColor(
                    status: focused.card.effectiveStatus, isDone: focused.agent.isDone, isSnoozed: false,
                    isPlanApproval: focused.agent.isPlanApproval, isAskingQuestion: focused.agent.isAskingQuestion,
                    staleness: focused.agent.staleness, theme: themeConfig.selectedTheme
                )
                RadialGradient(colors: [accent.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                BoardHeaderView(viewModel: viewModel, tagStore: tagStore)
                    .padding(.horizontal, 20)
                    .padding(.top, 34)
                    .padding(.bottom, 10)

                switch viewModel.mode {
                case .stats:
                    StatsModeView(viewModel: viewModel, tagStore: tagStore)
                        .padding(.horizontal, 20)
                case .conductor:
                    ConductorView(viewModel: viewModel, conductor: viewModel.conductor, tagStore: tagStore, store: store, theme: themeConfig.selectedTheme)
                        .padding(.horizontal, 20)
                case .board:
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(columns.filter { !viewModel.isCollapsed($0.column) }) { data in
                            BoardColumnView(
                                data: data,
                                viewModel: viewModel,
                                tagStore: tagStore,
                                theme: themeConfig.selectedTheme,
                                hostAppIcons: store.hostAppIcons,
                                customNames: store.customNames,
                                selectedCardId: selectedCardId
                            )
                        }
                        let collapsed = columns.filter { viewModel.isCollapsed($0.column) }
                        if !collapsed.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(collapsed) { data in
                                    CollapsedColumnTile(data: data, theme: themeConfig.selectedTheme) {
                                        viewModel.toggleCollapsed(data.column)
                                    }
                                }
                                Spacer()
                            }
                            .frame(width: 64)
                        }
                    }
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.collapsedColumns)
                }

                BoardFooterView()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }

            if viewModel.isHelpShown {
                BoardHelpOverlay { viewModel.isHelpShown = false }
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.isTagManagerShown) {
            TagManagerView(tagStore: tagStore) { viewModel.isTagManagerShown = false }
        }
        .sheet(isPresented: $viewModel.isInstructionsShown) {
            ConductorInstructionsView(conductor: viewModel.conductor) { viewModel.isInstructionsShown = false }
        }
        .onChange(of: columns.map { $0.cards.map(\.id) }) { _ in
            viewModel.clampSelection()
        }
    }
}

// MARK: - Header (title + filter chips)

private struct BoardHeaderView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject var tagStore: TagStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.create(size: 18))
                Text("Blob Board")
                    .font(.system(size: 17, weight: .semibold))
            }

            Divider().frame(height: 18)

            if viewModel.mode == .board {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(tagStore.tags.enumerated()), id: \.element.id) { index, tag in
                                FilterChip(
                                    title: tag.name,
                                    color: tag.color,
                                    shortcut: index < 9 ? "\(index + 1)" : nil,
                                    isOn: tagStore.activeFilterTagIds.contains(tag.id)
                                ) {
                                    tagStore.toggleFilter(tagId: tag.id)
                                    viewModel.clampSelection()
                                }
                            }
                            FilterChip(
                                title: "Untagged",
                                color: Color(white: 0.6),
                                shortcut: "N",
                                isOn: tagStore.filterUntagged
                            ) {
                                tagStore.toggleUntaggedFilter()
                                viewModel.clampSelection()
                            }
                            if tagStore.isFilterActive {
                                Button {
                                    tagStore.clearFilter()
                                    viewModel.clampSelection()
                                } label: {
                                    Label("Clear", systemImage: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Clear filter (0)")
                            }
                        }
                    }
                }
            }

            Spacer()

            ModeSwitcher(mode: $viewModel.mode)
                .help("Board ⌘1 · Conductor ⌘2 · Stats ⌘3")

            Button {
                viewModel.isTagManagerShown = true
            } label: {
                Label("Manage Tags", systemImage: "tag")
                    .font(.system(size: 11))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Add, edit, and describe tags (M)")

            Button {
                viewModel.isHelpShown = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Keyboard shortcuts (?)")
        }
    }
}

/// Custom because the native segmented picker flattens custom labels to plain text.
private struct ModeSwitcher: View {
    @Binding var mode: BoardViewModel.BoardMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BoardViewModel.BoardMode.allCases) { item in
                let selected = item == mode
                Button {
                    mode = item
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        HStack(spacing: 0) {
                            Image(systemName: "command").font(.system(size: 8, weight: .semibold))
                            Text("\(item.number)").font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(selected ? 0.22 : 0.1)))
                        .foregroundColor(selected ? .white.opacity(0.9) : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.clear))
                    .foregroundColor(selected ? .white : .primary.opacity(0.85))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeInOut(duration: 0.12), value: mode)
    }
}

struct FilterChip: View {
    let title: String
    let color: Color
    var shortcut: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isOn ? color.opacity(0.25) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(isOn ? color : Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundColor(isOn ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Column

private struct BoardColumnView: View {
    let data: BoardColumnData
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject var tagStore: TagStore
    let theme: ColorTheme
    let hostAppIcons: [Int: NSImage]
    let customNames: [String: String]
    let selectedCardId: String?

    private var accent: Color { data.column.color(theme: theme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: data.column.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                Text(data.column.title)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(data.cards.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.25)))
                    .foregroundColor(accent)
                if data.hiddenCount > 0 {
                    Text("+\(data.hiddenCount) filtered")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    viewModel.toggleCollapsed(data.column)
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Collapse column (C)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(viewModel.selectedColumn == data.column ? 0.18 : 0.10))
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(accent.opacity(0.5)).frame(height: 2).padding(.horizontal, 8).offset(y: 1)
            }
            .padding(.bottom, 2)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(data.cards) { card in
                            BoardCardView(
                                card: card,
                                isSelected: card.id == selectedCardId,
                                theme: theme,
                                displayName: customNames[card.agent.sessionId] ?? card.agent.directoryLabel,
                                hostAppIcon: hostAppIcons[card.agent.pid],
                                tags: tagStore.resolvedTags(for: card.agent.sessionId),
                                isInferring: tagStore.inferringSessionIds.contains(card.agent.sessionId),
                                inferenceError: tagStore.inferenceErrors[card.agent.sessionId],
                                onOpen: { viewModel.open(card) },
                                onSelect: { viewModel.select(card) },
                                onTagButton: {
                                    viewModel.select(card)
                                    viewModel.toggleTagEditor(for: card)
                                },
                                onSnoozeButton: {
                                    viewModel.select(card)
                                    if card.column == .snoozed {
                                        viewModel.unsnooze(card)
                                    } else {
                                        viewModel.toggleSnoozePicker(for: card)
                                    }
                                },
                                onDismiss: { viewModel.dismiss(card) }
                            )
                            .id(card.id)
                            .popover(isPresented: Binding(
                                get: { viewModel.tagEditorAgentId == card.id },
                                set: { if !$0 { viewModel.tagEditorAgentId = nil } }
                            ), arrowEdge: .trailing) {
                                TagEditorPopover(
                                    tagStore: tagStore,
                                    viewModel: viewModel,
                                    sessionId: card.agent.sessionId,
                                    onToggle: { viewModel.toggleTag($0, on: card) },
                                    onConfirmAll: {
                                        viewModel.confirmInferredTags(on: card)
                                        viewModel.tagEditorAgentId = nil
                                    },
                                    onReinfer: { viewModel.reinfer(card) },
                                    onManage: {
                                        viewModel.tagEditorAgentId = nil
                                        viewModel.isTagManagerShown = true
                                    }
                                )
                            }
                            .popover(isPresented: Binding(
                                get: { viewModel.snoozePickerAgentId == card.id },
                                set: { if !$0 { viewModel.snoozePickerAgentId = nil } }
                            ), arrowEdge: .trailing) {
                                SnoozeDurationPopover(highlightedIndex: viewModel.snoozeIndex) { duration in
                                    viewModel.snooze(card, for: duration)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.selectedRow) { _ in scrollToSelection(proxy) }
                .onChange(of: viewModel.selectedColumn) { _ in scrollToSelection(proxy) }
            }

            if data.cards.isEmpty {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(viewModel.selectedColumn == data.column ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(viewModel.selectedColumn == data.column ? 0.14 : 0.07), lineWidth: 1)
        )
        .overlay(alignment: .center) {
            if data.cards.isEmpty {
                Text(data.hiddenCount > 0 ? "All filtered out" : "Nothing here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard viewModel.selectedColumn == data.column, let card = viewModel.selectedCard else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(card.id, anchor: nil)
        }
    }
}

// MARK: - Collapsed column tile

private struct CollapsedColumnTile: View {
    let data: BoardColumnData
    let theme: ColorTheme
    let onExpand: () -> Void

    private var accent: Color { data.column.color(theme: theme) }

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: 6) {
                Image(systemName: data.column.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                Text("\(data.cards.count)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Text(data.column.title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.15), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Expand \(data.column.title)")
    }
}

// MARK: - Footer legend

private struct BoardFooterView: View {
    private let keys: [(String, String)] = [
        ("↑↓←→", "move"), ("↵", "open"), ("T", "tags"), ("S", "snooze"),
        ("⌫", "snooze/dismiss"), ("C", "collapse"), ("1–9", "filter"), ("0", "clear"), ("⌘1-3", "mode"), ("M", "manage"), ("?", "help"), ("esc", "close"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(keys, id: \.0) { key, label in
                HStack(spacing: 4) {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Help overlay

private struct BoardHelpOverlay: View {
    let onDismiss: () -> Void

    private let rows: [(String, String)] = [
        ("↑ ↓ / J K", "Move between cards in a column"),
        ("← → / H L / Tab", "Move between columns (skips empty ones)"),
        ("Return", "Deep-link to the selected session and close the board"),
        ("T", "Open the tag editor for the selected card"),
        ("  ↑ ↓ / Return", "…move the highlight and toggle (starts on the inferred tag)"),
        ("  1–9", "…toggle the nth tag (adds or confirms; removes when confirmed)"),
        ("  C", "…confirm every inferred tag on the card"),
        ("  R", "…run tag inference again"),
        ("S", "Snooze the selected card; unsnooze when snoozed"),
        ("  ↑ ↓ / Return", "…move the highlight and pick a duration (1–6 picks directly)"),
        ("U", "Unsnooze the selected card"),
        ("Delete", "Snooze; when already snoozed, dismiss the session"),
        ("1–9", "Toggle the nth tag in the filter bar"),
        ("N", "Toggle the Untagged filter"),
        ("0", "Clear the filter"),
        ("C", "Collapse the selected column into the right-hand strip (click a tile to expand)"),
        ("⌘1 / ⌘2 / ⌘3", "Switch to Board / Conductor / Stats (Esc returns to the board)"),
        ("Conductor", "↑ ↓ focus · Return open · ⌘Return send · 1–9 pick option · ⌥1–9 pick and send · S skip · Z snooze (↑ ↓ / Return, 1–6) · I instructions · R re-analyze"),
        ("Stats", "1 / 2 set the stats window; 3 / 4 / 5 set the history range"),
        ("M", "Manage tags (add, edit descriptions, delete)"),
        ("Esc", "Close popover, then close the board"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard")
                    .font(.system(size: 15, weight: .semibold))
                ForEach(rows, id: \.0) { key, text in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(key)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 130, alignment: .leading)
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Text("Press ? or Esc to close")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1)))
        }
    }
}

