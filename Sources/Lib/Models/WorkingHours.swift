import Foundation

/// Time outside Mon–Fri 09:00–17:00 local does not count as waiting.
struct WorkingHours {
    let startHour = 9
    let endHour = 17
    var calendar: Calendar = .current

    static let `default` = WorkingHours()

    private func isWorkday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    func activeSeconds(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        var total: TimeInterval = 0
        var dayStart = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while dayStart <= lastDay {
            if isWorkday(dayStart),
               let open = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayStart),
               let close = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: dayStart) {
                let from = max(open, start)
                let to = min(close, end)
                if to > from { total += to.timeIntervalSince(from) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = next
        }
        return total
    }
}
