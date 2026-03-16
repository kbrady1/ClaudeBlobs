import SwiftUI

struct CollapsedView: View {
    let agents: [Agent]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(agents.prefix(10)) { agent in
                AgentSpriteView(status: agent.status, size: 18)
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
            Capsule()
                .fill(Color(red: 0.165, green: 0.165, blue: 0.165).opacity(0.8)) // #2a2a2a
        )
    }
}
