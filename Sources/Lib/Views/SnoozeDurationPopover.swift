import SwiftUI

/// Popover for choosing how long to snooze a blob.
struct SnoozeDurationPopover: View {
    var highlightedIndex: Int = 0
    var onSelect: (SnoozeDuration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snooze for\u{2026}")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(SnoozeDuration.allCases.enumerated()), id: \.element) { index, duration in
                    Button {
                        onSelect(duration)
                    } label: {
                        HStack(spacing: 6) {
                            Text(duration.label)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(index + 1)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(highlightedIndex == index ? Color.white.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 160)
        .padding(12)
    }
}
