import Foundation

/// How long a snoozed blob stays hidden before it pops back into the visible list.
enum SnoozeDuration: String, CaseIterable, Identifiable {
    /// First, so it is the default highlighted option in every snooze menu.
    case indefinite
    case thirtyMinutes
    case oneHour
    case threeHours
    case tomorrowMorning
    case nextWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hr"
        case .threeHours: return "3 hrs"
        case .tomorrowMorning: return "Tomorrow, 8 AM"
        case .nextWeek: return "Next week"
        case .indefinite: return "Until next message"
        }
    }

    /// The moment the snooze should end, or nil for an indefinite snooze
    /// (the agent stays hidden until its status changes or it's manually woken).
    func wakeDate(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .threeHours:
            return now.addingTimeInterval(3 * 60 * 60)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
        case .nextWeek:
            var comps = DateComponents()
            comps.weekday = 2 // Monday
            let nextMonday = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) ?? now
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextMonday)
        case .indefinite:
            return nil
        }
    }
}
