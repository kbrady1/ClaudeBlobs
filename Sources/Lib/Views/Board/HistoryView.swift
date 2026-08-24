import SwiftUI
import Charts

struct HistoryView: View {
    @ObservedObject var history: SessionHistoryStore
    @ObservedObject var tagStore: TagStore
    let range: HistoryRange
    let onManageTags: () -> Void

    @State private var editingSessionId: String?

    private var records: [SessionRecord] { history.records(in: range) }

    private func resolvedTags(for record: SessionRecord) -> [(tag: AgentTag, source: TagSource)] {
        if record.isActive {
            return tagStore.resolvedTags(for: record.sessionId)
        }
        return record.tagIds.compactMap { id in
            guard let tag = tagStore.tag(id: id) else { return nil }
            return (tag, record.tagSources[id] ?? .confirmed)
        }
    }

    private func toggleTag(_ tagId: String, on record: SessionRecord) {
        if record.isActive {
            tagStore.toggleTag(tagId, on: record.sessionId)
            return
        }
        switch record.tagSources[tagId] {
        case nil, .inferred?:
            history.setTagSource(tagId, source: .confirmed, on: record.sessionId)
        case .confirmed?:
            history.setTagSource(tagId, source: nil, on: record.sessionId)
        }
    }

    private func label(for group: String) -> String {
        tagStore.tag(id: group)?.name ?? (group == HistoryStats.untagged ? "Untagged" : group)
    }

    private func color(for group: String) -> Color {
        tagStore.tag(id: group)?.color ?? ChartStyle.muted
    }

    private func groupOrder(for stats: HistoryStats) -> [String] {
        let present = Set(stats.perDay.map(\.group))
        return (tagStore.tags.map(\.id) + [HistoryStats.untagged]).filter(present.contains)
    }

    var body: some View {
        let records = self.records
        let stats = HistoryStats.compute(records: records, tagOrder: tagStore.tags.map(\.id))
        let groupOrder = groupOrder(for: stats)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ChartStyle.tile("Sessions", value: "\(stats.total)", detail: "last \(range.days) days", accent: ChartStyle.blue)
                ChartStyle.tile("Per active day", value: stats.activeDays == 0 ? "–" : String(format: "%.1f", Double(stats.total) / Double(stats.activeDays)), detail: "\(stats.activeDays) active day\(stats.activeDays == 1 ? "" : "s")")
                ChartStyle.tile("Running now", value: "\(stats.active)", detail: "still open", accent: ChartStyle.green)
                ChartStyle.tile("Median length", value: stats.medianDurationMinutes.map { BoardModel.formatElapsed(TimeInterval($0 * 60)) } ?? "–", detail: "ended sessions")
                ChartStyle.tile("Tagged", value: stats.total == 0 ? "–" : "\(Int((Double(stats.total - (stats.perTag.first { $0.key == HistoryStats.untagged }?.count ?? 0)) / Double(stats.total) * 100).rounded()))%", detail: "have ≥1 tag")
            }

            if stats.total == 0 {
                Text("No sessions recorded in this range yet. Sessions are recorded while the app is running.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
            } else {
                ChartStyle.card("Sessions per day", subtitle: "stacked by primary tag") {
                    Chart(stats.perDay) { bucket in
                        BarMark(
                            x: .value("Day", bucket.day, unit: .day),
                            y: .value("Sessions", bucket.count)
                        )
                        .foregroundStyle(by: .value("Tag", label(for: bucket.group)))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(
                        domain: groupOrder.map(label(for:)),
                        range: groupOrder.map { ChartStyle.vertical(color(for: $0)) }
                    )
                    .chartLegend(position: .top, alignment: .leading, spacing: 8)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : (range == .month ? 5 : 15))) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                                .foregroundStyle(ChartStyle.muted)
                        }
                    }
                    .chartYAxis { ChartStyle.yAxis }
                    .frame(height: 220)
                }

                HStack(alignment: .top, spacing: 12) {
                    ChartStyle.card("Sessions by tag", subtitle: "a session counts once per tag") {
                        Chart(stats.perTag) { item in
                            BarMark(
                                x: .value("Sessions", item.count),
                                y: .value("Tag", label(for: item.key))
                            )
                            .foregroundStyle(ChartStyle.horizontal(color(for: item.key)))
                            .cornerRadius(3)
                            .annotation(position: .trailing, spacing: 6) {
                                Text("\(item.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85))
                            }
                        }
                        .chartYScale(domain: stats.perTag.map { label(for: $0.key) })
                        .frame(height: max(120, CGFloat(stats.perTag.count) * 26))
                    }

                    ChartStyle.card("Top repositories", subtitle: "by session count") {
                        Chart(stats.perRepo) { item in
                            BarMark(
                                x: .value("Sessions", item.count),
                                y: .value("Repo", item.key)
                            )
                            .foregroundStyle(ChartStyle.horizontal(ChartStyle.blue))
                            .cornerRadius(3)
                            .annotation(position: .trailing, spacing: 6) {
                                Text("\(item.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85))
                            }
                        }
                        .chartYScale(domain: stats.perRepo.map(\.key))
                        .frame(height: max(120, CGFloat(stats.perRepo.count) * 26))
                    }
                }

                ChartStyle.card("Sessions", subtitle: "newest first") {
                    VStack(spacing: 0) {
                        ForEach(Array(records.reversed().prefix(50))) { record in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(record.isActive ? ChartStyle.green : ChartStyle.muted.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(record.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                Text(record.repo ?? "")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                Button {
                                    editingSessionId = record.id
                                } label: {
                                    HStack(spacing: 4) {
                                        let tags = resolvedTags(for: record)
                                        if tags.isEmpty {
                                            Text("+ tag")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        } else {
                                            ForEach(tags, id: \.tag.id) { entry in
                                                TagChip(tag: entry.tag, source: entry.source)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: Binding(
                                    get: { editingSessionId == record.id },
                                    set: { if !$0 { editingSessionId = nil } }
                                ), arrowEdge: .trailing) {
                                    HistoryTagEditorPopover(
                                        tagStore: tagStore,
                                        sourceFor: { tagId in
                                            resolvedTags(for: record).first { $0.tag.id == tagId }?.source
                                        },
                                        onToggle: { toggleTag($0, on: record) },
                                        onManage: {
                                            editingSessionId = nil
                                            onManageTags()
                                        }
                                    )
                                }
                                Spacer()
                                Text(Self.dateFormatter.string(from: record.firstSeenAt))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(record.isActive ? "running" : BoardModel.formatElapsed((record.endedAt ?? record.lastSeenAt).timeIntervalSince(record.firstSeenAt)))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f
    }()
}
