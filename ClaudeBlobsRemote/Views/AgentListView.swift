// ClaudeBlobsRemote/Views/AgentListView.swift
import SwiftUI

struct AgentListView: View {
    @ObservedObject var connectionManager: ConnectionManager
    var onUnpair: (() -> Void)? = nil

    /// Top-level agents only — sub-agents whose parent is present are filtered out.
    private var topLevelAgents: [Agent] {
        let sessionIds = Set(connectionManager.agents.map(\.sessionId))
        return connectionManager.agents.filter { agent in
            guard let parentId = agent.parentSessionId else { return true }
            // Show as top-level if parent is no longer in the list
            return !sessionIds.contains(parentId)
        }
    }

    var body: some View {
        NavigationStack {
            List(topLevelAgents) { agent in
                NavigationLink(value: agent.sessionId) {
                    AgentRow(agent: agent, appIconData: connectionManager.agentIconData[agent.sessionId], statusColorHex: connectionManager.agentColorHex[agent.sessionId])
                }
            }
            .navigationTitle("Agents")
            .navigationDestination(for: String.self) { sessionId in
                if let agent = connectionManager.agents.first(where: { $0.sessionId == sessionId }) {
                    AgentDetailView(agent: agent, connectionManager: connectionManager)
                }
            }
            .overlay {
                switch connectionManager.connectionState {
                case .disconnected:
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Offline")
                            .font(.title3)
                            .fontWeight(.medium)
                        if let error = connectionManager.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Text("Searching for ClaudeBlobs on your network...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .connecting:
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Connecting...")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                case .connected:
                    if topLevelAgents.isEmpty {
                        ContentUnavailableView(
                            "No Agents",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("No Claude agents are currently running")
                        )
                    }
                }
            }
            .toolbar {
                if let onUnpair {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Unpair", role: .destructive) {
                            onUnpair()
                        }
                        .font(.caption)
                    }
                }
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
    var statusColorHex: String? = nil

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
                appIconData: appIconData,
                statusColorHex: statusColorHex
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
//        if let hex = statusColorHex, let col = Color(hex: hex) {
//            return col
//        }

        // Fallback if no hex provided
        switch agent.status {
        case .permission: return .red
        case .waiting: return .orange
        case .working: return .blue
        case .starting: return .green
        case .compacting: return .purple
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
