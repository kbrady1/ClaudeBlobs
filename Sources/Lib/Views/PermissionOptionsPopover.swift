import SwiftUI

/// Popover showing a permission preview and options for an agent.
struct PermissionOptionsPopover: View {
    let agent: Agent
    let options: [String]
    let isLoading: Bool
    let onSelect: (Int) -> Void
    let onGoToAgent: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(12)
            } else {
                // Permission preview
                permissionPreview

                Divider()

                // Options
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(option)
                                .font(.system(size: 11))
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(optionColor(index: index).opacity(0.12))
                    )
                }

                Divider()

                // Go to Agent
                Button {
                    onGoToAgent()
                } label: {
                    HStack(spacing: 6) {
                        Text("\(options.count + 1).")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Label("Go to Agent", systemImage: "arrow.right.circle")
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private var permissionPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tool name
            Text(agent.permissionToolUseExpanded)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.red)
                .lineLimit(3)

            // Context from raw message or last message
            if let context = agent.rawLastMessage ?? agent.lastMessage, !context.isEmpty {
                Text(context)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.06))
                    )
            }
        }
    }

    private func optionColor(index: Int) -> Color {
        if index == options.count - 1 { return .red }
        if index == 0 { return .green }
        return .blue
    }
}
