// ClaudeBlobsRemote/Views/AgentDetailView.swift
import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @ObservedObject var connectionManager: ConnectionManager
    @State private var responseText = ""
    @State private var showingConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Last message
                if let message = agent.rawLastMessage ?? agent.lastMessage {
                    messageSection(message)
                }

                // Tool info
                if let tool = agent.lastToolUse, agent.status == .permission {
                    permissionSection(tool)
                }

                Spacer(minLength: 20)

                // Controls
                if agent.isCmuxSession {
                    controlsSection
                }
            }
            .padding()
        }
        .navigationTitle(agent.projectName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cwd = agent.cwd {
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Circle()
                    .fill(agent.status == .permission ? .orange : agent.status == .waiting ? .purple : .green)
                    .frame(width: 10, height: 10)
                Text(agent.status.displayName)
                    .font(.subheadline)
                if !agent.isCmuxSession {
                    Text("(view only)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func messageSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(agent.status == .permission ? "Last Message" : "Agent Question")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(message)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func permissionSection(_ tool: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Requesting Permission")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(tool)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        switch agent.status {
        case .permission:
            HStack(spacing: 16) {
                Button {
                    Task { await connectionManager.sendCommand(.deny, sessionId: agent.sessionId) }
                } label: {
                    Label("Deny", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    Task { await connectionManager.sendCommand(.approve, sessionId: agent.sessionId) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

        case .waiting where agent.waitReason != "done":
            // Quick replies
            HStack(spacing: 8) {
                ForEach(["Yes", "No", "Continue"], id: \.self) { reply in
                    Button(reply) {
                        Task { await connectionManager.sendCommand(.respond, sessionId: agent.sessionId, text: reply) }
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Free text
            HStack {
                TextField("Type a response...", text: $responseText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    guard !responseText.isEmpty else { return }
                    Task {
                        await connectionManager.sendCommand(.respond, sessionId: agent.sessionId, text: responseText)
                        responseText = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(responseText.isEmpty)
            }

        case .working, .starting, .compacting:
            Button {
                Task { await connectionManager.sendCommand(.interrupt, sessionId: agent.sessionId) }
            } label: {
                Label("Interrupt", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

        default:
            EmptyView()
        }
    }
}
