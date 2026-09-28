import Foundation

/// How long a snoozed blob stays hidden before it pops back into the visible list.
enum SnoozeDuration: String, CaseIterable, Identifiable {
    /// First, so it is the default highlighted option in every snooze menu.
    case untilNextMessage
    case thirtyMinutes
    case oneHour
    case threeHours
    case tomorrowMorning
    case nextWeek
    /// Stays snoozed through status changes until the user wakes it by hand.
    case indefinite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hr"
        case .threeHours: return "3 hrs"
        case .tomorrowMorning: return "Tomorrow, 8 AM"
        case .nextWeek: return "Next week"
        case .untilNextMessage: return "Until next message"
        case .indefinite: return "Indefinitely"
        }
    }

    /// The moment the snooze should end, or nil when no timer ends it.
    /// `.untilNextMessage` ends on the next status change. `.indefinite` ends
    /// only on a manual wake.
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
        case .untilNextMessage, .indefinite:
            return nil
        }
    }
}
