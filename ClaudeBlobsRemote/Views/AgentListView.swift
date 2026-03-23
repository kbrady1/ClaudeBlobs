// ClaudeBlobsRemote/Views/AgentListView.swift
import SwiftUI

struct AgentListView: View {
    @ObservedObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            List(connectionManager.agents) { agent in
                NavigationLink(value: agent.sessionId) {
                    AgentRow(agent: agent)
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
                .fill(connectionManager.connectionState == .connected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(connectionManager.connectionState == .connected ? "Connected" : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            // Blob placeholder — replace with AgentSpriteView port in v2
            Circle()
                .fill(statusColor)
                .frame(width: 36, height: 36)
                .overlay {
                    statusIcon
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }

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

    private var statusIcon: some View {
        Group {
            switch agent.status {
            case .permission: Image(systemName: "hand.raised.fill")
            case .waiting: Image(systemName: agent.waitReason == "done" ? "checkmark" : "questionmark")
            case .working: Image(systemName: "gear")
            case .starting: Image(systemName: "circle.dotted")
            case .compacting: Image(systemName: "arrow.trianglehead.2.clockwise")
            }
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
