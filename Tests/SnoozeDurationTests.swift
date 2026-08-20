import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("SnoozeDuration")
struct SnoozeDurationTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    @Test func indefiniteHasNoWakeDate() {
        #expect(SnoozeDuration.indefinite.wakeDate() == nil)
    }

    @Test func relativeDurationsAddTheExpectedInterval() {
        let now = Date()
        #expect(SnoozeDuration.thirtyMinutes.wakeDate(from: now)!.timeIntervalSince(now) == 30 * 60)
        #expect(SnoozeDuration.oneHour.wakeDate(from: now)!.timeIntervalSince(now) == 60 * 60)
        #expect(SnoozeDuration.threeHours.wakeDate(from: now)!.timeIntervalSince(now) == 3 * 60 * 60)
    }

    @Test func tomorrowMorningLandsAt8AMTheNextDay() {
        let cal = calendar
        // Wednesday 2026-08-19 3:00 PM PT
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 15))!
        let wake = SnoozeDuration.tomorrowMorning.wakeDate(from: now, calendar: cal)!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: wake)
        #expect(comps.year == 2026 && comps.month == 8 && comps.day == 20)
        #expect(comps.hour == 8 && comps.minute == 0)
    }

    @Test func nextWeekLandsOnTheFollowingMondayAt8AM() {
        let cal = calendar
        // Wednesday 2026-08-19 3:00 PM PT
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 15))!
        let wake = SnoozeDuration.nextWeek.wakeDate(from: now, calendar: cal)!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: wake)
        #expect(comps.weekday == 2) // Monday
        #expect(comps.year == 2026 && comps.month == 8 && comps.day == 24)
        #expect(comps.hour == 8 && comps.minute == 0)
    }
}
