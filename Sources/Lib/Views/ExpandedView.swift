import SwiftUI
import AppKit

struct ExpandedView: View {
    let agents: [Agent]
    let snoozedIds: Set<String>
    var notifiedIds: Set<String> = []
    var childAgents: [String: [Agent]] = [:]
    let selectedIndex: Int?
    var theme: ColorTheme = .trafficLight
    var showAppIcons: Bool = true
    var backgroundStyle: BackgroundStyle = .color(.black)
    let onAgentClick: (Agent) -> Void
    let onSnooze: (Agent) -> Void
    let onDismiss: (Agent) -> Void
    @Environment(\.notchInset) private var notchInset

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(agents.prefix(9).enumerated()), id: \.element.id) { index, agent in
                Button { onAgentClick(agent) } label: {
                    agentCard(agent, isSelected: selectedIndex == index)
                }
                .buttonStyle(.plain)
                .opacity(snoozedIds.contains(agent.sessionId) ? 0.45 : agent.status == .working ? 0.7 : 1.0)
            }
            if agents.count > 9 {
                Text("+\(agents.count - 9)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        }
        .padding(12)
        .background(
            Group {
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
            .padding(.top, -notchInset)
        )
    }

    private func agentCard(_ agent: Agent, isSelected: Bool = false) -> some View {
        let kids = childAgents[agent.sessionId] ?? []
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    AgentSpriteView(
                        status: agent.status,
                        size: 40,
                        isSnoozed: snoozedIds.contains(agent.sessionId),
                        theme: theme,
                        isCoding: agent.isCoding,
                        isSearching: agent.isSearching,
                        isExploring: agent.isExploring,
                        isMcpTool: agent.isMcpTool,
                        isTesting: agent.isTesting,
                        isDone: agent.isDone,
                        hasNotified: notifiedIds.contains(agent.id),
                        staleness: agent.staleness,
                        isPlanApproval: agent.isPlanApproval,
                        isAskingQuestion: agent.isAskingQuestion,
                        isBashPermission: agent.isBashPermission,
                        isFilePermission: agent.isFilePermission,
                        isWebPermission: agent.isWebPermission,
                        isMcpPermission: agent.isMcpPermission,
                        isGithubPermission: agent.isGithubPermission,
                        isGithubTool: agent.isGithubTool,
                        isTaskJustCompleted: agent.isTaskJustCompleted,
                        isInterrupted: agent.isInterrupted,
                        isToolFailure: agent.isToolFailure,
                        isAPIError: agent.isAPIError
                    )
                    .frame(width: 48, height: 44)
                    .overlay(alignment: .bottomLeading) {
                        if showAppIcons {
                            AppIconBadge(pid: agent.pid)
                        }
                    }

                    // Mini child blobs along the bottom
                    if !kids.isEmpty {
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
                        .offset(y: -7) // overlap parent by half child height
                    }
                }

                if !snoozedIds.contains(agent.sessionId) {
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

            Text(agent.directoryLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)

            ScrollingSpeechBubble(text: agent.speechBubbleText)
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

/// Shows the host app icon (VS Code, Cursor, Claude Desktop) in the bottom-left corner.
private struct AppIconBadge: View {
    let icon: NSImage?

    init(pid: Int) {
        self.icon = HostAppResolver.resolve(pid: pid)?.icon
    }

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.5), radius: 1)
                .offset(x: -5, y: 5)
        }
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
