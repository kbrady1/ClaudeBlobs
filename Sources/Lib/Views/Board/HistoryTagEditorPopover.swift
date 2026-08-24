import SwiftUI

/// Tag editor for a session in the History/Stats list. Unlike `TagEditorPopover`, this has no
/// keyboard-highlight index and no re-infer action — historical sessions have no live agent to re-run
/// inference against.
struct HistoryTagEditorPopover: View {
    @ObservedObject var tagStore: TagStore
    let sourceFor: (String) -> TagSource?
    let onToggle: (String) -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))
                .padding(.bottom, 4)

            ForEach(tagStore.tags) { tag in
                let source = sourceFor(tag.id)
                Button {
                    onToggle(tag.id)
                } label: {
                    HStack(spacing: 8) {
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(helpText(for: tag, source: source))
            }

            Divider().padding(.vertical, 4)

            Button(action: onManage) {
                Text("Manage…").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
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
