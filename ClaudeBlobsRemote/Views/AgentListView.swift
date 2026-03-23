// ClaudeBlobsRemote/Views/AgentListView.swift
import SwiftUI

struct AgentListView: View {
    @ObservedObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            List(connectionManager.agents) { agent in
                NavigationLink(value: agent.sessionId) {
                    AgentRow(agent: agent, appIconData: connectionManager.agentIconData[agent.sessionId])
                }
            }
            .navigationTitle("Agents")
            .navigationDestination(for: String.self) { sessionId in
                if let agent = connectionManager.agents.first(where: { $0.sessionId == sessionId }) {
                    AgentDetailView(agent: agent, connectionManager: connectionManager)
                }
            }
            .overlay {
                if connectionManager.agents.isEmpty {
                    ContentUnavailableView(
                        "No Agents",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("No Claude agents are currently running")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    connectionStatusIndicator
                }
            }
        }
    }

    private var connectionStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch connectionManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch connectionManager.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Offline"
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    var appIconData: Data? = nil

    var body: some View {
        HStack(spacing: 12) {
            AgentSpriteView(
                status: agent.status,
                size: 36,
                isCoding: agent.isCoding,
                isSearching: agent.isSearching,
                isExploring: agent.isExploring,
                isMcpTool: agent.isMcpTool,
                isTesting: agent.isTesting,
                isDone: agent.isDone,
                staleness: AgentStaleness(updatedAt: agent.updatedAt),
                isPlanApproval: agent.isPlanApproval,
                isAskingQuestion: agent.isAskingQuestion,
                isBashPermission: agent.isBashPermission,
                isFilePermission: agent.isFilePermission,
                isWebPermission: agent.isWebPermission,
                isMcpPermission: agent.isMcpPermission,
                isGithubPermission: agent.isGithubPermission,
                isGithubTool: agent.isGithubTool,
                isTaskJustCompleted: agent.isTaskJustCompleted,
                isInterrupted: agent.isInterrupted,
                isToolFailure: agent.isToolFailure,
                isAPIError: agent.isAPIError,
                appIconData: appIconData
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.projectName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if let preview = previewText {
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch agent.status {
        case .permission: return .orange
        case .waiting: return agent.waitReason == "done" ? .gray : .purple
        case .working: return .green
        case .starting: return .blue
        case .compacting: return .yellow
        }
    }

    private var statusText: String {
        switch agent.status {
        case .permission: return "Permission needed"
        case .waiting: return agent.waitReason == "done" ? "Done" : "Asking question"
        case .working: return "Working"
        case .starting: return "Starting"
        case .compacting: return "Compacting"
        }
    }

    private var previewText: String? {
        switch agent.status {
        case .permission: return agent.lastToolUse
        case .waiting: return agent.lastMessage
        default: return agent.lastToolUse
        }
    }
}
