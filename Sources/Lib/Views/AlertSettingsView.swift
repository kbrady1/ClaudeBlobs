import SwiftUI

struct AlertSettingsView: View {
    @ObservedObject var ntfyConfig: NtfyConfig
    @ObservedObject var soundConfig: SoundConfig
    var soundPlayer: SoundPlayer
    var ntfyScheduler: NtfyScheduler

    private let priorities = ["min", "low", "default", "high", "urgent"]
    private let sounds = SoundConfig.availableSounds

    var body: some View {
        Form {
            // MARK: - Sound Effects
            Section {
                soundRow(label: "Green (Starting)", color: .green, selection: $soundConfig.greenSound)
                soundRow(label: "Orange (Waiting)", color: .orange, selection: $soundConfig.orangeSound)
                soundRow(label: "Red (Permission)", color: .red, selection: $soundConfig.redSound)
            } header: {
                Toggle("Sound Effects", isOn: $soundConfig.isEnabled)
                    .font(.headline)
            }
            .disabled(!soundConfig.isEnabled)

            // MARK: - Push Notifications
            Section {
                TextField("Endpoint", text: $ntfyConfig.endpoint)
                TextField("Topic", text: $ntfyConfig.topic, prompt: Text("Required"))

                Section("Notify When") {
                    Toggle("Permission needed", isOn: $ntfyConfig.notifyOnPermission)
                    Toggle("Waiting for input", isOn: $ntfyConfig.notifyOnWaiting)
                    Toggle("Done", isOn: $ntfyConfig.notifyOnDone)
                }

                Stepper("Delay: \(ntfyConfig.delaySeconds)s", value: $ntfyConfig.delaySeconds, in: 0...300, step: 5)

                Section("Priority") {
                    Picker("Default", selection: $ntfyConfig.defaultPriority) {
                        ForEach(priorities, id: \.self) { Text($0) }
                    }
                    Picker("Permission", selection: $ntfyConfig.permissionPriority) {
                        ForEach(priorities, id: \.self) { Text($0) }
                    }
                }

                TextField("Tags", text: $ntfyConfig.tags, prompt: Text("e.g. robot"))

                Button("Send Test Notification") {
                    NtfyClient.send(
                        endpoint: ntfyConfig.endpoint,
                        topic: ntfyConfig.topic,
                        message: "Test notification from ClaudeBlobs",
                        title: "Test",
                        priority: ntfyConfig.defaultPriority,
                        tags: ntfyConfig.tags
                    )
                }
                .disabled(ntfyConfig.topic.isEmpty)
            } header: {
                Toggle("Push Notifications", isOn: Binding(
                    get: { ntfyConfig.isEnabled },
                    set: { newValue in
                        ntfyConfig.isEnabled = newValue
                        if !newValue { ntfyScheduler.cancelAll() }
                    }
                ))
                .font(.headline)
            }
            .disabled(!ntfyConfig.isEnabled)
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 560)
    }

    private func soundRow(label: String, color: Color, selection: Binding<String>) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Picker(label, selection: selection) {
                Text("None").tag("")
                ForEach(sounds, id: \.self) { Text($0) }
            }
            Button {
                soundPlayer.preview(selection.wrappedValue)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue.isEmpty)
        }
    }
}
