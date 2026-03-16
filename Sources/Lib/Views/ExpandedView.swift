import SwiftUI

struct ExpandedView: View {
    let agents: [Agent]
    let onAgentClick: (Agent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(agents.prefix(10)) { agent in
                agentCard(agent)
                    .onTapGesture { onAgentClick(agent) }
                    .opacity(agent.status == .working ? 0.7 : 1.0)
            }
            if agents.count > 10 {
                Text("+\(agents.count - 10)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        )
    }

    private func agentCard(_ agent: Agent) -> some View {
        VStack(spacing: 4) {
            AgentSpriteView(status: agent.status, size: 40)

            Text(agent.directoryLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)

            SpeechBubbleView(text: agent.speechBubbleText)
        }
        .frame(width: 80)
    }
}
