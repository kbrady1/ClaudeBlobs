// ClaudeBlobsRemote/Views/AgentDetailView.swift
import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @ObservedObject var connectionManager: ConnectionManager
    @State private var responseText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var statusColor: Color {
        if let hex = connectionManager.agentColorHex[agent.sessionId],
           let col = Color(hex: hex) {
            return col
        }
        return .blue
    }

    private var canRespond: Bool {
        agent.isCmuxSession && agent.status != .working && agent.status != .compacting
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status header card
                    statusCard

                    // Message content
                    if agent.status == .permission, let tool = agent.lastToolUse {
                        permissionCard(tool)
                    }

                    if let message = agent.rawLastMessage ?? agent.lastMessage {
                        messageCard(message)
                    }
                }
                .padding()
            }

            Divider()

            // Bottom controls — always visible, pinned to bottom
            if agent.isCmuxSession {
                controlsBar
                    .padding()
                    .background(.bar)
            }
        }
        .navigationTitle(agent.projectName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 12) {
            AgentSpriteView(
                status: agent.status,
                size: 48,
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
                appIconData: connectionManager.agentIconData[agent.sessionId],
                statusColorHex: connectionManager.agentColorHex[agent.sessionId]
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)

                if let cwd = agent.cwd {
                    Text(cwd)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !agent.isCmuxSession {
                Text("View Only")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Permission Card

    private func permissionCard(_ tool: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permission Request", systemImage: "hand.raised.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.red)

            Text(tool)
                .font(.system(.callout, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Message Card

    private func messageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(messageLabel, systemImage: messageIcon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Controls Bar

    @ViewBuilder
    private var controlsBar: some View {
        VStack(spacing: 12) {
            // Permission options from Claude — show actual menu items
            if agent.status == .permission {
                let options = connectionManager.agentPermissionOptions[agent.sessionId] ?? []
                if !options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Button {
                                Task { await connectionManager.sendCommand(.selectOption, sessionId: agent.sessionId, optionIndex: index) }
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.callout)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(permissionOptionTint(index: index, total: options.count))
                        }
                    }
                } else {
                    // Fallback if no options parsed
                    HStack(spacing: 12) {
                        Button {
                            Task { await connectionManager.sendCommand(.deny, sessionId: agent.sessionId) }
                        } label: {
                            Label("Deny", systemImage: "xmark")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button {
                            Task { await connectionManager.sendCommand(.approve, sessionId: agent.sessionId) }
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }

                // Escape to cancel
                Button {
                    Task { await connectionManager.sendCommand(.deny, sessionId: agent.sessionId) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            // Quick replies and text input — only for non-permission states
            if canRespond && agent.status != .permission {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickReplies, id: \.self) { reply in
                            Button(reply) {
                                Task { await connectionManager.sendCommand(.respond, sessionId: agent.sessionId, text: reply) }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                }

                // Text input
                HStack(spacing: 10) {
                    TextField("Send a message...", text: $responseText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .focused($isTextFieldFocused)
                        .onSubmit { sendResponse() }

                    Button(action: sendResponse) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(responseText.isEmpty ? .gray : statusColor)
                    }
                    .disabled(responseText.isEmpty)
                }
            }

            // Interrupt — available when working
            if agent.status == .working || agent.status == .starting || agent.status == .compacting {
                Button {
                    Task { await connectionManager.sendCommand(.interrupt, sessionId: agent.sessionId) }
                } label: {
                    Label("Interrupt", systemImage: "stop.circle")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    // MARK: - Helpers

    private func sendResponse() {
        guard !responseText.isEmpty else { return }
        let text = responseText
        responseText = ""
        Task { await connectionManager.sendCommand(.respond, sessionId: agent.sessionId, text: text) }
    }

    private var statusLabel: String {
        switch agent.status {
        case .permission: return "Needs Permission"
        case .waiting: return agent.waitReason == "done" ? "Done" : "Waiting for Response"
        case .working: return "Working"
        case .starting: return "Starting"
        case .compacting: return "Compacting"
        }
    }

    private var messageLabel: String {
        switch agent.status {
        case .permission: return "Context"
        case .waiting where agent.waitReason == "done": return "Summary"
        case .waiting: return "Question"
        default: return "Last Message"
        }
    }

    private var messageIcon: String {
        switch agent.status {
        case .permission: return "info.circle"
        case .waiting where agent.waitReason == "done": return "checkmark.circle"
        case .waiting: return "questionmark.bubble"
        default: return "text.bubble"
        }
    }

    private var quickReplies: [String] {
        switch agent.status {
        case .waiting where agent.waitReason == "done":
            return ["Thanks", "Start next task", "Make changes"]
        case .waiting:
            return ["Yes", "No", "Continue", "Skip"]
        default:
            return ["Yes", "No", "Continue"]
        }
    }

    private func permissionOptionTint(index: Int, total: Int) -> Color {
        // Last option is typically "No"/deny — red. Others are green/blue.
        if index == total - 1 { return .red }
        if index == 0 { return .green }
        return .blue
    }
}
