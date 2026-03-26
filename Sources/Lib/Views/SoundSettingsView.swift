import SwiftUI

struct SoundSettingsView: View {
    @ObservedObject var config: SoundConfig
    var player: SoundPlayer

    private let sounds = SoundConfig.availableSounds

    var body: some View {
        Form {
            Toggle("Enable Sound Effects", isOn: $config.isEnabled)

            Section("Sounds") {
                soundRow(label: "Green (Starting)", color: .green, selection: $config.greenSound)
                soundRow(label: "Orange (Waiting)", color: .orange, selection: $config.orangeSound)
                soundRow(label: "Red (Permission)", color: .red, selection: $config.redSound)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 240)
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
                player.preview(selection.wrappedValue)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue.isEmpty)
        }
    }
}
