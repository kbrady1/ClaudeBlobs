import SwiftUI
import AppKit

struct ExpandedView: View {
    let agents: [Agent]
    let snoozedIds: Set<String>
    var notifiedIds: Set<String> = []
    var childAgents: [String: [Agent]] = [:]
    let selectedIndex: Int?
    var theme: ColorTheme = .trafficLight
    var prominentStateChangesEnabled: Bool = true
    var showAppIcons: Bool = true
    var hostAppIcons: [Int: NSImage] = [:]
    var backgroundStyle: BackgroundStyle = .color(.black)
    var customNames: [String: String] = [:]
    let onAgentClick: (Agent) -> Void
    let onSnooze: (Agent) -> Void
    let onDismiss: (Agent) -> Void
    var onRename: ((Agent, String) -> Void)?
    var onClearName: ((Agent) -> Void)?
    var onRenameStateChanged: ((Bool) -> Void)?
    var permissionAgent: Agent?
    var permissionOptions: [String] = []
    var isLoadingPermission: Bool = false
    var onPermissionSelect: ((Agent, Int) -> Void)?
    var onPermissionGoToAgent: ((Agent) -> Void)?
    var onPermissionCancel: (() -> Void)?
    @Environment(\.notchInset) private var notchInset
    @State private var renamingAgent: Agent?
    @State private var renameText: String = ""
    /// Frozen snapshot of agents while rename popover is open, preventing reorder from killing the popover.
    @State private var frozenAgents: [Agent]?
    @State private var showPermissionHint = false
    @State private var permissionHintTimer: Timer?

    private var displayAgents: [Agent] {
        frozenAgents ?? agents
    }

    private func displayName(for agent: Agent) -> String {
        customNames[agent.sessionId] ?? agent.directoryLabel
    }

    private func beginRename(_ agent: Agent) {
        frozenAgents = agents
        renameText = displayName(for: agent)
        renamingAgent = agent
        onRenameStateChanged?(true)
    }

    private func endRename() {
        renamingAgent = nil
        frozenAgents = nil
        onRenameStateChanged?(false)
    }

    private func commitRename() {
        guard let agent = renamingAgent else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == agent.directoryLabel {
            onClearName?(agent)
        } else {
            onRename?(agent, trimmed)
        }
        endRename()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(displayAgents.prefix(9).enumerated()), id: \.element.id) { index, agent in
                Button { onAgentClick(agent) } label: {
                    agentCard(agent, isSelected: selectedIndex == index)
                }
                .buttonStyle(.plain)
                .opacity(snoozedIds.contains(agent.id) ? 0.45 : agent.status == .working ? 0.7 : 1.0)
                .contextMenu {
                    Button("Rename\u{2026}") { beginRename(agent) }
                    if customNames[agent.sessionId] != nil {
                        Button("Clear Name") { onClearName?(agent) }
                    }
                }
                .popover(isPresented: Binding(
                    get: { renamingAgent?.id == agent.id },
                    set: { if !$0 { endRename() } }
                )) {
                    RenamePopover(
                        text: $renameText,
                        hasCustomName: customNames[agent.sessionId] != nil,
                        onCommit: commitRename,
                        onClear: {
                            onClearName?(agent)
                            endRename()
                        }
                    )
                }
                .popover(isPresented: Binding(
                    get: { permissionAgent?.id == agent.id },
                    set: { if !$0 { onPermissionCancel?() } }
                )) {
                    PermissionOptionsPopover(
                        agent: agent,
                        options: permissionOptions,
                        isLoading: isLoadingPermission,
                        onSelect: { index in onPermissionSelect?(agent, index) },
                        onGoToAgent: { onPermissionGoToAgent?(agent) },
                        onCancel: { onPermissionCancel?() }
                    )
                }
            }
            if displayAgents.count > 9 {
                Text("+\(agents.count - 9)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        }
        .onAppear { showPermissionHintIfNeeded() }
        .onChange(of: selectedIndex) { _ in showPermissionHintIfNeeded() }
        .onChange(of: agents.map(\.status)) { _ in
            // Auto-dismiss permission popover if agent leaves permission state
            if let agent = permissionAgent,
               agents.first(where: { $0.id == agent.id })?.status != .permission {
                onPermissionCancel?()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameSelectedAgent)) { notification in
            guard let sessionId = notification.object as? String,
                  let agent = agents.first(where: { $0.sessionId == sessionId }) else { return }
            beginRename(agent)
        }
        .padding(12)
        .background(
            Group {
                if !displayAgents.isEmpty {
                    switch backgroundStyle {
                    case .color(let color):
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 0
                        )
                        .fill(color)
                    case .material:
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 0
                        )
                        .fill(.ultraThinMaterial)
                    }
                }
            }
            .padding(.top, -notchInset)
        )
    }

    private func showPermissionHintIfNeeded() {
        permissionHintTimer?.invalidate()
        guard let index = selectedIndex,
              index < displayAgents.count else {
            showPermissionHint = false
            return
        }
        let agent = displayAgents[index]
        if agent.status == .permission && agent.isCmuxSession {
            showPermissionHint = true
            permissionHintTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showPermissionHint = false
                    }
                }
            }
        } else {
            showPermissionHint = false
        }
    }

    private func effectiveStatus(_ agent: Agent) -> AgentStatus {
        Agent.effectiveStatus(of: agent, children: childAgents[agent.id] ?? [])
    }

    private func mostUrgentChild(_ agent: Agent) -> Agent? {
        Agent.mostUrgentChild(of: agent, children: childAgents[agent.id] ?? [])
    }

    /// Whether any visible agent has child sub-agents (used for uniform card height).
    private var anyAgentHasChildren: Bool {
        agents.prefix(9).contains { (childAgents[$0.id] ?? []).count > 1 }
    }

    private func agentCard(_ agent: Agent, isSelected: Bool = false) -> some View {
        let kids = childAgents[agent.id] ?? []
        let resolved = effectiveStatus(agent)
        let urgent = mostUrgentChild(agent)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    AgentSpriteView(
                        status: resolved,
                        size: 40,
                        isSnoozed: snoozedIds.contains(agent.id),
                        theme: theme,
                        prominentStateChangesEnabled: prominentStateChangesEnabled,
                        isCoding: agent.isCoding,
                        isSearching: agent.isSearching,
                        isExploring: agent.isExploring,
                        isMcpTool: agent.isMcpTool,
                        isTesting: agent.isTesting,
                        isDone: agent.isDone,
                        hasNotified: notifiedIds.contains(agent.id),
                        staleness: agent.staleness,
                        isPlanApproval: resolved == agent.status ? agent.isPlanApproval : (urgent?.isPlanApproval ?? false),
                        isAskingQuestion: resolved == agent.status ? agent.isAskingQuestion : (urgent?.isAskingQuestion ?? false),
                        isBashPermission: resolved == agent.status ? agent.isBashPermission : (urgent?.isBashPermission ?? false),
                        isFilePermission: resolved == agent.status ? agent.isFilePermission : (urgent?.isFilePermission ?? false),
                        isWebPermission: resolved == agent.status ? agent.isWebPermission : (urgent?.isWebPermission ?? false),
                        isMcpPermission: resolved == agent.status ? agent.isMcpPermission : (urgent?.isMcpPermission ?? false),
                        isGithubPermission: resolved == agent.status ? agent.isGithubPermission : (urgent?.isGithubPermission ?? false),
                        isGithubTool: agent.isGithubTool,
                        isTaskJustCompleted: agent.isTaskJustCompleted,
                        isInterrupted: agent.isInterrupted,
                        isToolFailure: agent.isToolFailure,
                        isAPIError: agent.isAPIError,
                        appIcon: showAppIcons ? hostAppIcons[agent.pid] : nil,
                        appIconShowsBorder: true
                    )
                    .frame(width: 48, height: 44)

                    // Uniform spacer for child blobs area; overlay actual blobs with offset
                    if anyAgentHasChildren {
                        Spacer()
                            .overlay {
                                if kids.count > 1 {
                                    HStack(spacing: 2) {
                                        ForEach(kids.prefix(3)) { child in
                                            MiniAgentBlob(status: child.status, staleness: child.staleness, theme: theme)
                                        }
                                        if kids.count > 3 {
                                            Text("+\(kids.count - 3)")
                                                .font(.system(size: 6, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .offset(y: -5)
                                }
                            }
                            .frame(height: 8)
                    }
                }

                if !snoozedIds.contains(agent.id) {
                    Button {
                        onSnooze(agent)
                    } label: {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .padding(3)
                            .background(
                                Circle()
                                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                                    .background(Circle().fill(.ultraThinMaterial))
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onDismiss(agent)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(3)
                            .background(
                                Circle()
                                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                                    .background(Circle().fill(.ultraThinMaterial))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(displayName(for: agent))
                .font(.system(size: 9))
                .foregroundColor(customNames[agent.sessionId] != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)

            ScrollingSpeechBubble(text: agent.speechBubbleText)
                .opacity(showPermissionHint && isSelected && agent.status == .permission && agent.isCmuxSession ? 0 : 1)
                .overlay {
                    if showPermissionHint && isSelected && agent.status == .permission && agent.isCmuxSession {
                        Text("⇧↵ to respond")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.orange)
                            .transition(.opacity)
                    }
                }
        }
        .frame(width: 80)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

extension Notification.Name {
    static let renameSelectedAgent = Notification.Name("renameSelectedAgent")
}

/// Popover for renaming a blob.
private struct RenamePopover: View {
    @Binding var text: String
    var hasCustomName: Bool
    var onCommit: () -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit { onCommit() }
            HStack(spacing: 8) {
                if hasCustomName {
                    Button("Clear") { onClear() }
                }
                Spacer()
                Button("Rename") { onCommit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

/// A tiny 14px blob representing a sub-agent, showing status color and simple face.
private struct MiniAgentBlob: View {
    let status: AgentStatus
    var staleness: AgentStaleness = .active
    var theme: ColorTheme = .trafficLight

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(status.color(for: theme))
                .frame(width: 14, height: 14)
            // Minimal face: two dots for eyes
            if staleness == .stale || staleness == .hung {
                // X eyes
                Path { path in
                    path.move(to: CGPoint(x: 3, y: 3))
                    path.addLine(to: CGPoint(x: 6, y: 6))
                    path.move(to: CGPoint(x: 6, y: 3))
                    path.addLine(to: CGPoint(x: 3, y: 6))
                    path.move(to: CGPoint(x: 8, y: 3))
                    path.addLine(to: CGPoint(x: 11, y: 6))
                    path.move(to: CGPoint(x: 11, y: 3))
                    path.addLine(to: CGPoint(x: 8, y: 6))
                }
                .stroke(.black, lineWidth: 1)
            } else {
                Circle().fill(.black).frame(width: 3, height: 3).offset(x: -2, y: -1)
                Circle().fill(.black).frame(width: 3, height: 3).offset(x: 2, y: -1)
            }
        }
        .saturation(staleness == .hung ? 0 : 1)
    }
}
