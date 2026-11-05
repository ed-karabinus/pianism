import Foundation
import Testing

@testable import PianismCore

struct DailyReminderTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    @Test("SET-1: the reminders start today while the time is still to come, and run 14 days")
    func startsTodayBeforeTheTime() throws {
        let calendar = try calendar("America/Los_Angeles")
        let dates = DailyReminder.dates(
            atMinute: 18 * 60 + 30, after: try date(calendar, 2027, 1, 30, 18, 29), skippingToday: false, in: calendar)

        #expect(dates.count == 14)
        #expect(dates.first == DateComponents(year: 2027, month: 1, day: 30, hour: 18, minute: 30))
        #expect(dates.last == DateComponents(year: 2027, month: 2, day: 12, hour: 18, minute: 30))
    }

    @Test("SET-1: at or past the time, the reminders start tomorrow, still 14 of them")
    func startsTomorrowFromTheTime() throws {
        let calendar = try calendar("America/Los_Angeles")
        for now in [try date(calendar, 2027, 1, 30, 18), try date(calendar, 2027, 1, 30, 23, 59)] {
            let dates = DailyReminder.dates(atMinute: 18 * 60, after: now, skippingToday: false, in: calendar)

            #expect(dates.count == 14)
            #expect(dates.first == DateComponents(year: 2027, month: 1, day: 31, hour: 18, minute: 0))
        }
    }

    @Test("SET-1: with today's practice done, the reminders start tomorrow, still 14 of them")
    func skipsToday() throws {
        let calendar = try calendar("America/Los_Angeles")
        let dates = DailyReminder.dates(
            atMinute: 18 * 60, after: try date(calendar, 2027, 1, 30, 9), skippingToday: true, in: calendar)

        #expect(dates.count == 14)
        #expect(dates.first == DateComponents(year: 2027, month: 1, day: 31, hour: 18, minute: 0))
        #expect(dates.last == DateComponents(year: 2027, month: 2, day: 13, hour: 18, minute: 0))
    }

    @Test("SET-1: a reminder stays at its time across a clock change, one a day")
    func keepsItsTimeAcrossAClockChange() throws {
        let calendar = try calendar("America/Los_Angeles")
        // The clocks go forward on 2027-03-14.
        let dates = DailyReminder.dates(
            atMinute: 18 * 60, after: try date(calendar, 2027, 3, 13, 12), skippingToday: false, in: calendar)

        #expect(dates.map(\.day) == [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26])
        #expect(Set(dates.map(\.hour)) == [18])
    }

    @Test("SET-1: a time the clocks skip that day still comes that day, whatever the zone")
    func aSkippedTimeStillComes() throws {
        let losAngeles = try calendar("America/Los_Angeles")
        // 2:30 AM doesn't exist on 2027-03-14 there.
        let spring = DailyReminder.dates(
            atMinute: 2 * 60 + 30, after: try date(losAngeles, 2027, 3, 13, 12), skippingToday: false, in: losAngeles)
        #expect(spring.map(\.day) == [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27])
        #expect(spring.first?.hour == 3)

        // In Santiago the clocks go forward at midnight, so 12:30 AM doesn't exist on 2027-09-05.
        let santiago = try calendar("America/Santiago")
        let midnight = DailyReminder.dates(
            atMinute: 30, after: try date(santiago, 2027, 9, 4, 12), skippingToday: false, in: santiago)
        #expect(midnight.map(\.day) == [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
    }

    @Test("SET-1: a reminder names no time zone, so it follows the phone")
    func namesNoTimeZone() throws {
        let calendar = try calendar("Asia/Tokyo")
        let dates = DailyReminder.dates(
            atMinute: 8 * 60, after: try date(calendar, 2027, 6, 1, 7), skippingToday: false, in: calendar)

        #expect(dates.allSatisfy { $0.timeZone == nil && $0.calendar == nil })
    }
}
