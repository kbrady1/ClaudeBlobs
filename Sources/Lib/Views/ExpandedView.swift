import SwiftUI

struct ExpandedView: View {
    let agents: [Agent]
    let snoozedIds: Set<String>
    var notifiedIds: Set<String> = []
    var childAgents: [String: [Agent]] = [:]
    let selectedIndex: Int?
    let onAgentClick: (Agent) -> Void
    let onSnooze: (Agent) -> Void
    let onDismiss: (Agent) -> Void

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
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 0
            )
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
                        isCoding: agent.isCoding,
                        isSearching: agent.isSearching,
                        isDone: agent.isDone,
                        hasNotified: notifiedIds.contains(agent.id),
                        staleness: agent.staleness,
                        isPlanApproval: agent.isPlanApproval,
                        isAskingQuestion: agent.isAskingQuestion,
                        isTaskJustCompleted: agent.isTaskJustCompleted
                    )
                    .frame(width: 48, height: 44)

                    // Mini child blobs along the bottom
                    if !kids.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(kids.prefix(3)) { child in
                                MiniAgentBlob(status: child.status, staleness: child.staleness)
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

/// A tiny 14px blob representing a sub-agent, showing status color and simple face.
private struct MiniAgentBlob: View {
    let status: AgentStatus
    var staleness: AgentStaleness = .active

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(status.color)
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
