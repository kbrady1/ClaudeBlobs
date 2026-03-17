import SwiftUI

struct CollapsedView: View {
    let agents: [Agent]
    let newAgentIds: Set<String>
    var notifiedIds: Set<String> = []
    /// Resolved children per agent session ID, for deriving effective isCoding.
    var childAgents: [String: [Agent]] = [:]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(agents.prefix(10)) { agent in
                WavingEntrance(shouldWave: newAgentIds.contains(agent.id)) {
                    AgentSpriteView(
                        status: agent.status,
                        size: 18,
                        isCoding: effectiveIsCoding(agent),
                        isSearching: effectiveIsSearching(agent),
                        isDone: agent.isDone,
                        hasNotified: notifiedIds.contains(agent.id),
                        staleness: agent.staleness,
                        isPlanApproval: agent.isPlanApproval
                    )
                }
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
