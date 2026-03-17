import SwiftUI
import Carbon.HIToolbox

struct HotkeyRecorderView: View {
    @Binding var config: HotkeyConfig
    let onChanged: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Hotkey")
            Spacer()
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "Press keys…" : config.displayString)
                    .frame(minWidth: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotkeyConfig.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier
            guard mods != 0 else { return nil }

            config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: mods)
            config.save()
            stopRecording()
            onChanged()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
