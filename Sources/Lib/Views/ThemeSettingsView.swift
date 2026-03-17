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
        }
        .padding(.vertical, 8)
        .frame(width: 320)
    }
}
