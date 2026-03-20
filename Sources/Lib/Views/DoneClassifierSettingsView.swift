import SwiftUI

struct DoneClassifierSettingsView: View {
    @ObservedObject var config: DoneClassifierConfig

    var body: some View {
        Form {
            Section("AI Done Detection") {
                if config.isAppleIntelligenceAvailable {
                    Toggle("Apple Intelligence", isOn: $config.appleIntelligenceEnabled)
                    Text("Uses on-device AI to determine if an agent is done or asking a question.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Apple Intelligence requires macOS 26 or later.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 200)
    }
}
