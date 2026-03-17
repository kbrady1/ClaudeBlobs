import SwiftUI

struct NtfySettingsView: View {
    @ObservedObject var config: NtfyConfig

    private let priorities = ["min", "low", "default", "high", "urgent"]

    var body: some View {
        Form {
            Toggle("Enable Push Notifications", isOn: $config.isEnabled)

            Section("Server") {
                TextField("Endpoint", text: $config.endpoint)
                TextField("Topic", text: $config.topic, prompt: Text("Required"))
            }

            Section("Notify When") {
                Toggle("Permission needed", isOn: $config.notifyOnPermission)
                Toggle("Waiting for input", isOn: $config.notifyOnWaiting)
                Toggle("Done", isOn: $config.notifyOnDone)
            }

            Section("Timing") {
                Stepper("Delay: \(config.delaySeconds)s", value: $config.delaySeconds, in: 0...300, step: 5)
            }

            Section("Priority") {
                Picker("Default", selection: $config.defaultPriority) {
                    ForEach(priorities, id: \.self) { Text($0) }
                }
                Picker("Permission", selection: $config.permissionPriority) {
                    ForEach(priorities, id: \.self) { Text($0) }
                }
            }

            Section("Tags") {
                TextField("Tags", text: $config.tags, prompt: Text("e.g. robot"))
            }

            Button("Send Test Notification") {
                NtfyClient.send(
                    endpoint: config.endpoint,
                    topic: config.topic,
                    message: "Test notification from ClaudeBlobs",
                    title: "Test",
                    priority: config.defaultPriority,
                    tags: config.tags
                )
            }
            .disabled(config.topic.isEmpty)
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 480)
    }
}
