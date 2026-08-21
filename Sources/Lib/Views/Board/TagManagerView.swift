import SwiftUI

struct TagManagerView: View {
    @ObservedObject var tagStore: TagStore
    let onDone: () -> Void

    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newColor = AgentTag.palette[0]
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Tags")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("Auto-infer tags for new sessions", isOn: $tagStore.inferenceEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }

            Text("Each description tells you what the tag means and tells the inference step how to recognize it from a session's first prompt.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(tagStore.tags) { tag in
                        TagEditorRow(tag: tag, onChange: { tagStore.updateTag($0) }) {
                            tagStore.removeTag(id: tag.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 200, maxHeight: 360)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("New tag")
                    .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 8) {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    ColorPaletteRow(selected: $newColor)
                    Spacer()
                }
                TextField("Description — what it is and how to infer it", text: $newDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    if let addError {
                        Text(addError).font(.system(size: 10)).foregroundColor(.orange)
                    }
                    Spacer()
                    Button("Add Tag") { addTag() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }

            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private func addTag() {
        if tagStore.addTag(name: newName, description: newDescription, colorHex: newColor) != nil {
            newName = ""
            newDescription = ""
            addError = nil
            let used = Set(tagStore.tags.map(\.colorHex))
            newColor = AgentTag.palette.first { !used.contains($0) } ?? AgentTag.palette[0]
        } else {
            addError = "A tag with that name already exists."
        }
    }
}

private struct TagEditorRow: View {
    let tag: AgentTag
    let onChange: (AgentTag) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var colorHex: String
    @State private var confirmingDelete = false
    @State private var commitTask: Task<Void, Never>?

    init(tag: AgentTag, onChange: @escaping (AgentTag) -> Void, onDelete: @escaping () -> Void) {
        self.tag = tag
        self.onChange = onChange
        self.onDelete = onDelete
        _name = State(initialValue: tag.name)
        _description = State(initialValue: tag.description)
        _colorHex = State(initialValue: tag.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ColorPaletteRow(selected: Binding(
                    get: { colorHex },
                    set: { colorHex = $0; commit() }
                ))
                TextField("Name", text: $name, onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Text(tag.id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if confirmingDelete {
                    Button("Delete") { onDelete() }
                        .controlSize(.small)
                        .tint(.red)
                    Button("Keep") { confirmingDelete = false }
                        .controlSize(.small)
                } else {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Delete tag (removes it from every session)")
                }
            }
            TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .font(.system(size: 11))
                .onSubmit(commit)
                .onChange(of: description) { _ in
                    commitTask?.cancel()
                    commitTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        commit()
                    }
                }
                .onDisappear {
                    commitTask?.cancel()
                    commit()
                }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private func commit() {
        var updated = tag
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        updated.name = trimmed.isEmpty ? tag.name : trimmed
        updated.description = description
        updated.colorHex = colorHex
        if updated != tag { onChange(updated) }
    }
}

struct ColorPaletteRow: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AgentTag.palette, id: \.self) { hex in
                Button {
                    selected = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle().strokeBorder(Color.white, lineWidth: selected == hex ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
