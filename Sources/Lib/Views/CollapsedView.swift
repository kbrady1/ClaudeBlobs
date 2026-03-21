import SwiftUI
import AppKit

struct CollapsedView: View {
    let agents: [Agent]
    let newAgentIds: Set<String>
    var notifiedIds: Set<String> = []
    /// Resolved children per agent identity, for deriving effective isCoding.
    var childAgents: [String: [Agent]] = [:]
    var hideWhileCollapsed: Bool = false
    var peekingIds: Set<String> = []
    var theme: ColorTheme = .trafficLight
    var prominentStateChangesEnabled: Bool = true
    var showAppIcons: Bool = false
    var hostAppIcons: [Int: NSImage] = [:]
    var backgroundStyle: BackgroundStyle?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(agents.prefix(10)) { agent in
                let isHidden = hideWhileCollapsed && !peekingIds.contains(agent.id)
                WavingEntrance(shouldWave: newAgentIds.contains(agent.id)) {
                    let resolved = effectiveStatus(agent)
                    let urgent = mostUrgentChild(agent)
                    AgentSpriteView(
                        status: resolved,
                        size: 18,
                        theme: theme,
                        prominentStateChangesEnabled: prominentStateChangesEnabled,
                        isCoding: effectiveIsCoding(agent),
                        isSearching: effectiveIsSearching(agent),
                        isExploring: effectiveIsExploring(agent),
                        isMcpTool: effectiveIsMcpTool(agent),
                        isTesting: effectiveIsTesting(agent),
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
                        isGithubTool: effectiveIsGithubTool(agent),
                        isTaskJustCompleted: agent.isTaskJustCompleted,
                        isInterrupted: agent.isInterrupted,
                        isToolFailure: agent.isToolFailure,
                        isAPIError: agent.isAPIError,
                        appIcon: showAppIcons ? hostAppIcons[agent.pid] : nil
                    )
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

    private func effectiveStatus(_ agent: Agent) -> AgentStatus {
        Agent.effectiveStatus(of: agent, children: childAgents[agent.id] ?? [])
    }

    private func mostUrgentChild(_ agent: Agent) -> Agent? {
        Agent.mostUrgentChild(of: agent, children: childAgents[agent.id] ?? [])
    }

    /// Parent's own isCoding takes precedence; otherwise derive from children.
    private func effectiveIsCoding(_ agent: Agent) -> Bool {
        if agent.isCoding { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
        return kids.contains { $0.isCoding }
    }

    /// Parent's own isSearching takes precedence; otherwise derive from children.
    private func effectiveIsSearching(_ agent: Agent) -> Bool {
        if agent.isSearching { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
        return kids.contains { $0.isSearching }
    }

    /// Parent's own isExploring takes precedence; otherwise derive from children.
    private func effectiveIsExploring(_ agent: Agent) -> Bool {
        if agent.isExploring { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
        return kids.contains { $0.isExploring }
    }

    /// Parent's own isMcpTool takes precedence; otherwise derive from children.
    private func effectiveIsMcpTool(_ agent: Agent) -> Bool {
        if agent.isMcpTool { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
        return kids.contains { $0.isMcpTool }
    }

    /// Parent's own isGithubTool takes precedence; otherwise derive from children.
    private func effectiveIsGithubTool(_ agent: Agent) -> Bool {
        if agent.isGithubTool { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
        return kids.contains { $0.isGithubTool }
    }

    /// Parent's own isTesting takes precedence; otherwise derive from children.
    private func effectiveIsTesting(_ agent: Agent) -> Bool {
        if agent.isTesting { return true }
        guard let kids = childAgents[agent.id], !kids.isEmpty else { return false }
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

