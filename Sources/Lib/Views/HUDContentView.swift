import SwiftUI

struct HUDContentView: View {
    @ObservedObject var store: AgentStore
    @State private var isExpanded = false
    @State private var isHovering = false
    let onAgentClick: (Agent) -> Void

    var body: some View {
        Group {
            if isExpanded {
                ExpandedView(agents: store.agents, onAgentClick: onAgentClick)
            } else {
                CollapsedView(agents: store.collapsedAgents)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                withAnimation(.spring(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if isHovering { return }
                    withAnimation(.spring(duration: 0.2)) {
                        isExpanded = false
                    }
                }
            }
        }
        .onChange(of: isExpanded) { expanded in
            NotificationCenter.default.post(
                name: .hudExpansionChanged,
                object: nil,
                userInfo: ["expanded": expanded]
            )
        }
    }
}

extension Notification.Name {
    static let hudExpansionChanged = Notification.Name("hudExpansionChanged")
}
