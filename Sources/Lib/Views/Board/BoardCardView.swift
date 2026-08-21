import SwiftUI

struct BoardCardView: View {
    let card: BoardCard
    let isSelected: Bool
    let theme: ColorTheme
    let displayName: String
    let hostAppIcon: NSImage?
    let tags: [(tag: AgentTag, source: TagSource)]
    let isInferring: Bool
    let inferenceError: String?
    let onOpen: () -> Void
    let onSelect: () -> Void
    let onTagButton: () -> Void
    let onSnoozeButton: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    private var agent: Agent { card.agent }
    private var statusColor: Color {
        AgentSpriteView.blobColor(
            status: card.effectiveStatus, isDone: agent.isDone, isSnoozed: card.column == .snoozed,
            isPlanApproval: agent.isPlanApproval, isAskingQuestion: agent.isAskingQuestion,
            staleness: agent.staleness, theme: theme
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            location
            activity
            if !card.children.isEmpty { childrenRow }
            tagRow
        }
        .padding(10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: isHovering ? 0.17 : 0.14))
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: statusColor.opacity(0.22), location: 0),
                                .init(color: statusColor.opacity(0.0), location: 0.45),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.white.opacity(0.85) : statusColor.opacity(0.25),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering in
            isHovering = hovering
            if hovering { onSelect() }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .help("Click to open this session")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentSpriteView(
                status: card.effectiveStatus,
                size: 30,
                isSnoozed: card.column == .snoozed,
                theme: theme,
                isCoding: agent.isCoding,
                isSearching: agent.isSearching,
                isExploring: agent.isExploring,
                isMcpTool: agent.isMcpTool,
                isTesting: agent.isTesting,
                isDone: agent.isDone,
                staleness: agent.staleness,
                isPlanApproval: agent.isPlanApproval,
                isAskingQuestion: agent.isAskingQuestion,
                isBashPermission: agent.isBashPermission,
                isFilePermission: agent.isFilePermission,
                isWebPermission: agent.isWebPermission,
                isMcpPermission: agent.isMcpPermission,
                isGithubPermission: agent.isGithubPermission,
                isGithubTool: agent.isGithubTool,
                isScheduledWakeup: agent.isScheduledWakeup,
                isMonitorActive: agent.isMonitorActive,
                isInterrupted: agent.isInterrupted,
                isToolFailure: agent.isToolFailure,
                isAPIError: agent.isAPIError,
                useGlassBlob: true,
                animated: false
            )
            .frame(width: 34, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(BoardModel.formatElapsed(context.date.timeIntervalSince(card.enteredAt)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .help("Time in this column")
                HStack(spacing: 4) {
                    if card.column == .snoozed {
                        iconButton("bell.fill", help: "Unsnooze (S)", action: onSnoozeButton)
                        iconButton("xmark", help: "Dismiss session (⌫)", action: onDismiss)
                    } else {
                        iconButton("moon.fill", help: "Snooze… (S)", action: onSnoozeButton)
                    }
                }
            }
        }
    }

    private var statusLabel: String {
        if card.column == .snoozed {
            if let until = card.snoozeUntil {
                return "Snoozed until \(Self.timeFormatter.string(from: until))"
            }
            return "Snoozed"
        }
        switch card.effectiveStatus {
        case .waiting:
            if agent.isInterrupted { return "Interrupted" }
            if agent.isAPIError { return "API error" }
            if agent.isToolFailure { return "Tool failed" }
            if card.isClockBearing && agent.isDone { return agent.isMonitorActive ? "Monitoring" : "Scheduled" }
            return agent.isDone ? "Done" : "Asking a question"
        case .permission:
            return agent.isPlanApproval ? "Plan approval" : "Needs permission"
        default:
            return card.effectiveStatus.displayName
        }
    }

    @ViewBuilder
    private var location: some View {
        if let cwd = agent.cwd, let repo = RepoInfo.resolve(cwd: cwd) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(repo.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                if let branch = repo.branch {
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        HStack(spacing: 5) {
            if let hostAppIcon {
                Image(nsImage: hostAppIcon)
                    .resizable()
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(locationText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(agent.cwd ?? "")
            if agent.isCmuxSession {
                locationBadge("cmux")
            } else if agent.isSupersetSession {
                locationBadge("superset")
            }
            if agent.provider == .openCode {
                locationBadge("opencode")
            }
        }
    }

    private var locationText: String {
        if let cwd = agent.cwd, !cwd.isEmpty { return BoardModel.shortPath(cwd) }
        return "Claude Desktop"
    }

    private func locationBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = latestMessage {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let tool = latestTool {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: card.effectiveStatus == .permission ? "lock.shield" : "wrench.and.screwdriver")
                        .font(.system(size: 9))
                        .foregroundColor(card.effectiveStatus == .permission ? theme.color(for: .permission) : .secondary)
                        .padding(.top, 2)
                    Text(tool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if latestMessage == nil && latestTool == nil {
                Text(card.effectiveStatus == .starting ? "Starting up…" : "No activity yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
    }

    private var latestMessage: String? {
        if let wakeup = agent.scheduledWakeupText, agent.status == .waiting { return wakeup }
        let text = agent.notificationMessage
        return text.isEmpty ? nil : text
    }

    private var latestTool: String? {
        guard agent.lastToolUse != nil else { return nil }
        let text = card.effectiveStatus == .permission
            ? agent.permissionToolUseExpanded
            : Agent.formatToolForDisplay(agent.lastToolUse ?? "", imperative: false, maxCommandLength: 120)
        return text.isEmpty ? nil : text
    }

    private var childrenRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("\(card.children.count) sub-agent\(card.children.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            ForEach(card.children.prefix(6)) { child in
                RoundedRectangle(cornerRadius: 2)
                    .fill(child.status.color(for: theme))
                    .frame(width: 8, height: 8)
                    .help(child.agentType ?? child.directoryLabel)
            }
        }
    }

    private var tagRow: some View {
        HStack(spacing: 5) {
            ForEach(tags, id: \.tag.id) { entry in
                TagChip(tag: entry.tag, source: entry.source)
            }
            if isInferring {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("inferring…")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            } else if let inferenceError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .help("Tag inference failed: \(inferenceError)")
            }
            Spacer(minLength: 0)
            Button(action: onTagButton) {
                Image(systemName: "tag")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Edit tags (T)")
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .padding(4)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct TagChip: View {
    let tag: AgentTag
    let source: TagSource
    var shortcut: String?

    var body: some View {
        HStack(spacing: 3) {
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(tag.name)
                .font(.system(size: 9, weight: source == .confirmed ? .semibold : .regular))
                .italic(source == .inferred)
            if source == .inferred {
                Text("?")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(tag.color)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(source == .confirmed ? tag.color.opacity(0.3) : Color.clear)
        )
        .overlay(
            Capsule().strokeBorder(
                tag.color.opacity(source == .confirmed ? 0.9 : 0.7),
                style: StrokeStyle(lineWidth: 1, dash: source == .inferred ? [3, 2] : [])
            )
        )
        .foregroundColor(source == .confirmed ? .primary : .secondary)
        .help(source == .confirmed ? "\(tag.name) — confirmed" : "\(tag.name) — inferred, not yet confirmed")
    }
}
