import SwiftUI

/// Bridges keyboard-driven expand/collapse from AppDelegate into SwiftUI.
final class HUDExpansionState: ObservableObject {
    @Published var isKeyboardExpanded = false
    @Published var selectedIndex: Int = 0

    func toggle(agentCount: Int) {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            isKeyboardExpanded.toggle()
        }
        if isKeyboardExpanded {
            selectedIndex = 0
        }
    }

    func collapse() {
        guard isKeyboardExpanded else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            isKeyboardExpanded = false
        }
        selectedIndex = 0
    }

    func cycleForward(agentCount: Int) {
        guard agentCount > 0 else { return }
        selectedIndex = (selectedIndex + 1) % agentCount
    }

    func cycleBackward(agentCount: Int) {
        guard agentCount > 0 else { return }
        selectedIndex = (selectedIndex - 1 + agentCount) % agentCount
    }
}

struct HUDContentView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var expansionState: HUDExpansionState
    @ObservedObject var ntfyScheduler: NtfyScheduler
    @State private var isHoverExpanded = false
    @State private var isHovering = false
    @State private var knownAgentIds: Set<String> = []
    @State private var newAgentIds: Set<String> = []
    let onAgentClick: (Agent) -> Void

    private var isExpanded: Bool {
        isHoverExpanded || expansionState.isKeyboardExpanded
    }

    private var resolvedChildren: [String: [Agent]] {
        var result: [String: [Agent]] = [:]
        for (parentId, childIds) in store.childSessionIds {
            result[parentId] = childIds.compactMap { id in store.agents.first { $0.sessionId == id } }
        }
        return result
    }



    var body: some View {
        VStack(spacing: 0) {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            isHoverExpanded = true
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if isHovering { return }
                            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                                isHoverExpanded = false
                            }
                        }
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: store.agents.map(\.id)) { ids in
            let currentIds = Set(ids)
            newAgentIds = currentIds.subtracting(knownAgentIds)
            knownAgentIds = currentIds
        }
        .onChange(of: isExpanded) { expanded in
            if !expanded { newAgentIds = [] }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isExpanded {
            ExpandedView(
                agents: store.sortedTopLevelAgents,
                snoozedIds: store.snoozedSessionIds,
                notifiedIds: ntfyScheduler.notifiedSessionIds,
                childAgents: resolvedChildren,
                selectedIndex: expansionState.isKeyboardExpanded ? expansionState.selectedIndex : nil,
                onAgentClick: { agent in
                    onAgentClick(agent)
                    expansionState.collapse()
                },
                onSnooze: { store.snooze($0) },
                onDismiss: { store.dismiss($0) }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        } else {
            CollapsedView(
                agents: store.collapsedAgents,
                newAgentIds: newAgentIds,
                notifiedIds: ntfyScheduler.notifiedSessionIds,
                childAgents: resolvedChildren,
                hideWhileCollapsed: store.hideWhileCollapsed,
                peekingIds: store.peekingIds
            )
            .transition(.opacity.combined(with: .scale(scale: 1.05, anchor: .top)))
        }
    }
}
