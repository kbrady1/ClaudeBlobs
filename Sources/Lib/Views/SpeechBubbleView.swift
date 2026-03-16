import SwiftUI

struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .frame(maxWidth: 80)
        }
    }
}
