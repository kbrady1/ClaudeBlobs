import SwiftUI
import Charts

enum ChartStyle {
    static let muted = Color(red: 0x89 / 255, green: 0x87 / 255, blue: 0x81 / 255)
    static let blue = Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255)
    static let green = Color(red: 0x19 / 255, green: 0x9E / 255, blue: 0x70 / 255)
    static let orange = Color(red: 0xD9 / 255, green: 0x59 / 255, blue: 0x26 / 255)
    static let red = Color(red: 0xE6 / 255, green: 0x67 / 255, blue: 0x67 / 255)

    static func vertical(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
    }

    static func horizontal(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.35), color], startPoint: .leading, endPoint: .trailing)
    }

    static func card<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    static func tile(_ title: String, value: String, detail: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
                if let accent {
                    RoundedRectangle(cornerRadius: 10).fill(
                        LinearGradient(colors: [accent.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
            }
        )
    }

    static var yAxis: some AxisContent {
        AxisMarks(position: .leading) { _ in
            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
            AxisValueLabel().foregroundStyle(muted)
        }
    }
}

struct StatsModeView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject var tagStore: TagStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Stats", symbol: "gauge.with.dots.needle.33percent") {
                    Picker("", selection: $viewModel.statsWindowHours) {
                        Text("24 hours").tag(24)
                        Text("7 days").tag(168)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                    keyHint("1 / 2")
                }
                StatsSectionView(history: viewModel.history, tagStore: tagStore, windowHours: viewModel.statsWindowHours)

                sectionHeader("History", symbol: "clock.arrow.circlepath") {
                    Picker("", selection: $viewModel.historyRange) {
                        ForEach(HistoryRange.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .labelsHidden()
                    keyHint("3 / 4 / 5")
                }
                .padding(.top, 10)
                HistoryView(history: viewModel.history, tagStore: tagStore, range: viewModel.historyRange)
            }
            .padding(.bottom, 10)
        }
    }

    private func sectionHeader<Controls: View>(_ title: String, symbol: String, @ViewBuilder controls: () -> Controls) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            controls()
        }
    }

    private func keyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
    }
}

struct StatsSectionView: View {
    @ObservedObject var history: SessionHistoryStore
    @ObservedObject var tagStore: TagStore
    let windowHours: Int

    private var window: TimeInterval { TimeInterval(windowHours) * 3600 }
    private var step: TimeInterval { windowHours <= 24 ? 900 : 3600 }          // 15 min / 1 h samples
    private var bucket: TimeInterval { windowHours <= 24 ? 3600 : 6 * 3600 }   // starts per 1 h / 6 h

    private func label(for key: String) -> String {
        tagStore.tag(id: key)?.name ?? "Untagged"
    }

    private func color(for key: String) -> Color {
        tagStore.tag(id: key)?.color ?? ChartStyle.muted
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let records = Array(history.records.values)
            let order = tagStore.tags.map(\.id)
            let stats = BoardStats.compute(records: records, window: window, tagOrder: order, now: now)
            let concurrency = BoardStats.concurrencySeries(records: records, window: window, step: step, now: now)
            let starts = BoardStats.startsSeries(records: records, window: window, step: bucket, now: now)
            let tagged = stats.sessions - (stats.byTag.first { $0.key == HistoryStats.untagged }?.count ?? 0)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ChartStyle.tile("Sessions", value: "\(stats.sessions)", detail: "last \(windowHours <= 24 ? "24 hours" : "7 days")", accent: ChartStyle.blue)
                    ChartStyle.tile("Peak concurrent", value: "\(stats.maxConcurrent)", detail: String(format: "avg %.1f running", stats.meanConcurrent), accent: ChartStyle.green)
                    ChartStyle.tile("Idle wait", value: stats.idleWait.map { BoardModel.formatElapsed($0.median) } ?? "–", detail: stats.idleWait.map { "median · p75 \(BoardModel.formatElapsed($0.p75)) · \($0.count) episodes" } ?? "no episodes", accent: ChartStyle.orange)
                    ChartStyle.tile("Attention wait", value: stats.attentionWait.map { BoardModel.formatElapsed($0.median) } ?? "–", detail: stats.attentionWait.map { "median · p75 \(BoardModel.formatElapsed($0.p75)) · \($0.count) episodes" } ?? "no episodes", accent: ChartStyle.red)
                    ChartStyle.tile("Tagged", value: stats.sessions == 0 ? "–" : "\(Int((Double(tagged) / Double(stats.sessions) * 100).rounded()))%", detail: "\(tagged) of \(stats.sessions) sessions")
                }

                HStack(alignment: .top, spacing: 12) {
                    ChartStyle.card("Concurrent sessions", subtitle: windowHours <= 24 ? "sampled every 15 min" : "sampled hourly") {
                        Chart(concurrency) { sample in
                            AreaMark(x: .value("Time", sample.time), y: .value("Running", sample.value))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(ChartStyle.vertical(ChartStyle.green).opacity(0.6))
                            LineMark(x: .value("Time", sample.time), y: .value("Running", sample.value))
                                .interpolationMethod(.stepEnd)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .foregroundStyle(ChartStyle.green)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: windowHours <= 24 ? .hour : .day, count: windowHours <= 24 ? 4 : 1)) { _ in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                AxisValueLabel(format: windowHours <= 24 ? .dateTime.hour() : .dateTime.weekday(.abbreviated))
                                    .foregroundStyle(ChartStyle.muted)
                            }
                        }
                        .chartYAxis { ChartStyle.yAxis }
                        .chartYScale(domain: 0...max(1, (concurrency.map(\.value).max() ?? 1) + 1))
                        .frame(height: 180)
                    }

                    ChartStyle.card("Sessions started", subtitle: windowHours <= 24 ? "per hour" : "per 6 hours") {
                        Chart(starts) { sample in
                            BarMark(x: .value("Time", sample.time, unit: windowHours <= 24 ? .hour : .hour), y: .value("Started", sample.value), width: .ratio(0.7))
                                .foregroundStyle(ChartStyle.vertical(ChartStyle.blue))
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: windowHours <= 24 ? .hour : .day, count: windowHours <= 24 ? 4 : 1)) { _ in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                AxisValueLabel(format: windowHours <= 24 ? .dateTime.hour() : .dateTime.weekday(.abbreviated))
                                    .foregroundStyle(ChartStyle.muted)
                            }
                        }
                        .chartYAxis { ChartStyle.yAxis }
                        .frame(height: 180)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    ChartStyle.card("Sessions by tag", subtitle: "a session counts once per tag") {
                        if stats.byTag.isEmpty {
                            Text("No sessions in this window").font(.system(size: 11)).foregroundColor(.secondary)
                        } else {
                            Chart(stats.byTag, id: \.key) { entry in
                                BarMark(x: .value("Sessions", entry.count), y: .value("Tag", label(for: entry.key)))
                                    .foregroundStyle(ChartStyle.horizontal(color(for: entry.key)))
                                    .cornerRadius(3)
                                    .annotation(position: .trailing, spacing: 6) {
                                        Text("\(entry.count)")
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
                            .chartYScale(domain: stats.byTag.map { label(for: $0.key) })
                            .frame(height: max(120, CGFloat(stats.byTag.count) * 26))
                        }
                    }

                    ChartStyle.card("Wait times", subtitle: "Idle vs Needs Attention · episodes started in the window") {
                        let rows = waitRows(stats)
                        if rows.isEmpty {
                            Text("No Idle / Needs Attention episodes yet").font(.system(size: 11)).foregroundColor(.secondary)
                        } else {
                            Chart(rows) { row in
                                BarMark(x: .value("Minutes", row.minutes), y: .value("Stat", row.stat))
                                    .foregroundStyle(ChartStyle.horizontal(row.color))
                                    .position(by: .value("Column", row.column))
                                    .cornerRadius(3)
                                    .annotation(position: .trailing, spacing: 6) {
                                        Text(BoardModel.formatElapsed(row.minutes * 60))
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                            }
                            .chartForegroundStyleScale(["Idle": ChartStyle.orange, "Needs Attention": ChartStyle.red])
                            .chartLegend(position: .top, alignment: .leading)
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85))
                                }
                            }
                            .chartYScale(domain: ["Median", "p75", "Max", "Mean"])
                            .frame(height: 190)
                        }
                    }
                }
            }
        }
    }

    private struct WaitRow: Identifiable {
        let column: String
        let stat: String
        let minutes: Double
        let color: Color
        var id: String { column + stat }
    }

    private func waitRows(_ stats: BoardStats) -> [WaitRow] {
        var rows: [WaitRow] = []
        for (name, spread, color) in [("Idle", stats.idleWait, ChartStyle.orange), ("Needs Attention", stats.attentionWait, ChartStyle.red)] {
            guard let spread else { continue }
            rows.append(WaitRow(column: name, stat: "Median", minutes: spread.median / 60, color: color))
            rows.append(WaitRow(column: name, stat: "p75", minutes: spread.p75 / 60, color: color))
            rows.append(WaitRow(column: name, stat: "Max", minutes: spread.max / 60, color: color))
            rows.append(WaitRow(column: name, stat: "Mean", minutes: spread.mean / 60, color: color))
        }
        return rows
    }
}
