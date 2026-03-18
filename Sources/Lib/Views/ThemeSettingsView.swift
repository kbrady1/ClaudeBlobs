import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var config: ThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ColorTheme.allCases, id: \.self) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        config.selectedTheme = theme
                    }
                } label: {
                    HStack {
                        Image(systemName: config.selectedTheme == theme ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(config.selectedTheme == theme ? .accentColor : .secondary)
                            .frame(width: 20)

                        Text(theme.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 4) {
                            ForEach(AgentStatus.allCases, id: \.self) { status in
                                Circle()
                                    .fill(status.color(for: theme))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if theme != ColorTheme.allCases.last {
                    Divider().padding(.leading, 40)
                }
            }

            Divider().padding(.vertical, 8)

            Toggle(isOn: $config.backgroundEnabled) {
                Text("Background")
            }
            .padding(.horizontal, 12)

            if config.backgroundEnabled {
                Toggle(isOn: $config.backgroundMaterial) {
                    Text("Material (blur)")
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                if !config.backgroundMaterial {
                    HStack {
                        Text("Color")
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: $config.backgroundColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 320)
    }
}
