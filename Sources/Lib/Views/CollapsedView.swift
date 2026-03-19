import SwiftUI
import AppKit

struct CollapsedView: View {
    let agents: [Agent]
    let newAgentIds: Set<String>
    var notifiedIds: Set<String> = []
    /// Resolved children per agent session ID, for deriving effective isCoding.
    var childAgents: [String: [Agent]] = [:]
    var hideWhileCollapsed: Bool = false
    var peekingIds: Set<String> = []
    var theme: ColorTheme = .trafficLight
    var showAppIcons: Bool = false
    var backgroundStyle: BackgroundStyle?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(agents.prefix(10)) { agent in
                let isHidden = hideWhileCollapsed && !peekingIds.contains(agent.id)
                WavingEntrance(shouldWave: newAgentIds.contains(agent.id)) {
                    AgentSpriteView(
                        status: agent.status,
                        size: 18,
                        theme: theme,
                        isCoding: effectiveIsCoding(agent),
                        isSearching: effectiveIsSearching(agent),
                        isExploring: effectiveIsExploring(agent),
                        isMcpTool: effectiveIsMcpTool(agent),
                        isTesting: effectiveIsTesting(agent),
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
                        isGithubTool: effectiveIsGithubTool(agent),
                        isTaskJustCompleted: agent.isTaskJustCompleted,
                        isInterrupted: agent.isInterrupted,
                        isToolFailure: agent.isToolFailure,
                        isAPIError: agent.isAPIError
                    )
                    .overlay(alignment: .bottomLeading) {
                        if showAppIcons {
                            CollapsedAppIconBadge(pid: agent.pid)
                        }
                    }
                }
                .opacity(isHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isHidden)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.01).combined(with: .opacity),
                        removal: .scale(scale: 0.01).combined(with: .opacity).combined(with: .offset(y: 8))
                    )
                )
            }
            if agents.count > 10 {
                Text("+\(agents.count - 10)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            Group {
                if let backgroundStyle {
                    switch backgroundStyle {
                    case .color(let color):
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 0
                        )
                        .fill(color)
                    case .material:
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 0
                        )
                        .fill(.ultraThinMaterial)
                    }
                }
            }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: agents.map(\.id))
    }

    /// Parent's own isCoding takes precedence; otherwise derive from children.
    private func effectiveIsCoding(_ agent: Agent) -> Bool {
        if agent.isCoding { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isCoding }
    }

    /// Parent's own isSearching takes precedence; otherwise derive from children.
    private func effectiveIsSearching(_ agent: Agent) -> Bool {
        if agent.isSearching { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isSearching }
    }

    /// Parent's own isExploring takes precedence; otherwise derive from children.
    private func effectiveIsExploring(_ agent: Agent) -> Bool {
        if agent.isExploring { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isExploring }
    }

    /// Parent's own isMcpTool takes precedence; otherwise derive from children.
    private func effectiveIsMcpTool(_ agent: Agent) -> Bool {
        if agent.isMcpTool { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isMcpTool }
    }

    /// Parent's own isGithubTool takes precedence; otherwise derive from children.
    private func effectiveIsGithubTool(_ agent: Agent) -> Bool {
        if agent.isGithubTool { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isGithubTool }
    }

    /// Parent's own isTesting takes precedence; otherwise derive from children.
    private func effectiveIsTesting(_ agent: Agent) -> Bool {
        if agent.isTesting { return true }
        guard let kids = childAgents[agent.sessionId], !kids.isEmpty else { return false }
        return kids.contains { $0.isTesting }
    }
}

/// Plays a brief wave (rotation wiggle) when the content first appears, only if `shouldWave` is true.
private struct WavingEntrance<Content: View>: View {
    let shouldWave: Bool
    @ViewBuilder let content: Content
    @State private var waveAngle: Double = 0

    var body: some View {
        content
            .rotationEffect(.degrees(waveAngle))
            .onAppear {
                guard shouldWave else { return }
                // Quick wiggle sequence: tilt right, left, right, settle
                withAnimation(.easeInOut(duration: 0.12)) { waveAngle = 15 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeInOut(duration: 0.12)) { waveAngle = -12 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    withAnimation(.easeInOut(duration: 0.12)) { waveAngle = 8 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    withAnimation(.easeInOut(duration: 0.15)) { waveAngle = 0 }
                }
            }
    }
}

/// Smaller app icon badge for collapsed blobs (10px).
private struct CollapsedAppIconBadge: View {
    let icon: NSImage?

    init(pid: Int) {
        self.icon = HostAppResolver.resolve(pid: pid)?.icon
    }

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 10, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.5), radius: 1)
                .offset(x: -3, y: 3)
        }
    }
}
