import SwiftUI

private struct NotchInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var notchInset: CGFloat {
        get { self[NotchInsetKey.self] }
        set { self[NotchInsetKey.self] = newValue }
    }
}

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
    @ObservedObject var themeConfig: ThemeConfig
    @Environment(\.notchInset) private var notchInset
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
            result[parentId] = childIds.compactMap { id in store.agents.first { $0.id == id } }
        }
        return result
    }



    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, notchInset)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if !isHovering { return }
                            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                                isHoverExpanded = true
                            }
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

    private var resolvedBackgroundStyle: BackgroundStyle {
        themeConfig.backgroundMaterial ? .material : .color(themeConfig.backgroundColor)
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
                theme: themeConfig.selectedTheme,
                showAppIcons: store.appIconVisibility != .never,
                backgroundStyle: themeConfig.backgroundEnabled ? resolvedBackgroundStyle : .color(.black),
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
                peekingIds: store.peekingIds,
                theme: themeConfig.selectedTheme,
                showAppIcons: store.appIconVisibility == .always,
                backgroundStyle: themeConfig.backgroundEnabled ? resolvedBackgroundStyle : nil
            )
            .transition(.opacity.combined(with: .scale(scale: 1.05, anchor: .top)))
        }
    }
}
