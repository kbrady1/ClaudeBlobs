import SwiftUI

struct ExpandedView: View {
    let agents: [Agent]
    let snoozedIds: Set<String>
    var notifiedIds: Set<String> = []
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
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AgentSpriteView(status: agent.status, size: 40, isSnoozed: snoozedIds.contains(agent.sessionId), isCoding: agent.isCoding, isDone: agent.isDone, hasNotified: notifiedIds.contains(agent.id))
                    .frame(width: 48, height: 44)

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
