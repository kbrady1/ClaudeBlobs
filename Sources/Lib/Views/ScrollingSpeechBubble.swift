import SwiftUI

struct ScrollingSpeechBubble: View {
    let text: String

    @State private var scrollOffset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var overflow: CGFloat {
        max(0, textWidth - containerWidth + 4)
    }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: TextWidthKey.self, value: g.size.width)
                    }
                )
                .offset(x: overflow > 0 ? -scrollOffset : 0)
                .frame(maxWidth: 68, alignment: .leading)
                .clipped()
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: ContainerWidthKey.self, value: g.size.width)
                    }
                )
                .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
                .onPreferenceChange(ContainerWidthKey.self) { containerWidth = $0 }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .onAppear { beginScroll() }
                .onChange(of: text) { _ in
                    scrollOffset = 0
                    beginScroll()
                }
        }
    }

    private var maxScroll: CGFloat {
        // Scroll at most 60pt worth regardless of overflow, so speed stays consistent
        min(overflow, 60)
    }

    private func beginScroll() {
        scrollOffset = 0
        guard overflow > 0 else { return }
        withAnimation(
            .linear(duration: 5.0)
            .delay(1.0)
            .repeatForever(autoreverses: false)
        ) {
            scrollOffset = maxScroll
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
