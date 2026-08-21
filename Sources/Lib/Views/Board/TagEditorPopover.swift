import SwiftUI

struct TagEditorPopover: View {
    @ObservedObject var tagStore: TagStore
    @ObservedObject var viewModel: BoardViewModel
    let sessionId: String
    let onToggle: (String) -> Void
    let onConfirmAll: () -> Void
    let onReinfer: () -> Void
    let onManage: () -> Void

    private var hasInferred: Bool {
        tagStore.assignments(for: sessionId).contains { $0.source == .inferred }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tags")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if tagStore.inferringSessionIds.contains(sessionId) {
                    ProgressView().controlSize(.mini)
                    Text("inferring…").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            ForEach(Array(tagStore.tags.enumerated()), id: \.element.id) { index, tag in
                let source = tagStore.source(of: tag.id, on: sessionId)
                let highlighted = viewModel.tagEditorIndex == index
                Button {
                    viewModel.tagEditorIndex = index
                    onToggle(tag.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(index < 9 ? "\(index + 1)" : "")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 10)
                        Image(systemName: checkSymbol(for: source))
                            .font(.system(size: 12))
                            .foregroundColor(source == nil ? .secondary : tag.color)
                            .frame(width: 14)
                        Circle().fill(tag.color).frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.system(size: 12, weight: source == .confirmed ? .semibold : .regular))
                        Spacer()
                        if let source {
                            Text(source == .confirmed ? "confirmed" : "inferred")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(source == .confirmed ? tag.color : .secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(
                                    Capsule().strokeBorder(
                                        source == .confirmed ? tag.color.opacity(0.7) : Color.secondary.opacity(0.5),
                                        style: StrokeStyle(lineWidth: 1, dash: source == .inferred ? [3, 2] : [])
                                    )
                                )
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(highlighted ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { if $0 { viewModel.tagEditorIndex = index } }
                .help(helpText(for: tag, source: source))
            }

            if let error = tagStore.inferenceErrors[sessionId] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 10) {
                if hasInferred {
                    footerButton("Confirm all", key: "C", action: onConfirmAll)
                }
                footerButton("Re-infer", key: "R", action: onReinfer)
                    .disabled(!tagStore.inferenceEnabled || tagStore.inferringSessionIds.contains(sessionId))
                Spacer()
                footerButton("Manage…", key: "M", action: onManage)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func footerButton(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11))
                Text(key)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func checkSymbol(for source: TagSource?) -> String {
        switch source {
        case .confirmed?: return "checkmark.square.fill"
        case .inferred?: return "questionmark.square.dashed"
        case nil: return "square"
        }
    }

    private func helpText(for tag: AgentTag, source: TagSource?) -> String {
        let action: String
        switch source {
        case .confirmed?: action = "Confirmed — click to remove"
        case .inferred?: action = "Inferred — click to confirm"
        case nil: action = "Click to add"
        }
        return tag.description.isEmpty ? action : "\(action)\n\n\(tag.description)"
    }
}
