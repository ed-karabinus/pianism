import Foundation
import Testing

@testable import PianismCore

struct PracticeWeekTests {
    @Test(
        "HIS-2: a week starts on the calendar's first weekday and has seven days, oldest first, with each day's total",
        arguments: [(1, 11), (2, 12)])
    func aWeekStartsOnTheFirstWeekday(firstWeekday: Int, startDay: Int) throws {
        let calendar = try calendar(firstWeekday: firstWeekday)
        // Thursday the 15th, and Monday the 12th, which starts a week beginning on Monday but not on Sunday.
        let thursday = try session(at: date(2026, 10, 15, 8, 0, in: calendar), minutes: 30)
        let monday = try session(at: date(2026, 10, 12, 19, 0, in: calendar), minutes: 20)
        let days = PracticeDay.group([thursday, monday], in: calendar)

        let week = PracticeWeek(containing: try date(2026, 10, 15, 20, 0, in: calendar), days: days, in: calendar)

        let starts = try (0..<7).map { try date(2026, 10, startDay + $0, 0, 0, in: calendar) }
        #expect(week.days.map(\.start) == starts)
        let expected: [TimeInterval] = firstWeekday == 1 ? [0, 20, 0, 0, 30, 0, 0] : [20, 0, 0, 30, 0, 0, 0]
        #expect(week.days.map(\.total) == expected.map { $0 * 60 })
        #expect(week.total == 50 * 60)
    }

    @Test("HIS-2: sessions outside the week don't count toward it")
    func otherWeeksDontCount() throws {
        let calendar = try calendar(firstWeekday: 2)
        let lastSunday = try session(at: date(2026, 10, 11, 23, 30, in: calendar), minutes: 60)
        let nextMonday = try session(at: date(2026, 10, 19, 0, 0, in: calendar), minutes: 10)
        let days = PracticeDay.group([lastSunday, nextMonday], in: calendar)

        let week = PracticeWeek(containing: try date(2026, 10, 15, 8, 0, in: calendar), days: days, in: calendar)

        #expect(week.total == 0)
        #expect(week.days.allSatisfy { $0.sessions.isEmpty })
    }

    @Test(
        "HIS-2: a week with a daylight-saving change still has seven days, one per date",
        arguments: [
            ("America/Los_Angeles", 2027, 3, 14), ("America/Los_Angeles", 2027, 11, 7),
            ("America/Santiago", 2027, 9, 5),
        ])
    func daylightSavingWeeks(zone: String, year: Int, month: Int, day: Int) throws {
        // A week from Sunday, the day the clocks change, so its later days start 23 or 25 hours apart. In
        // Santiago they change at midnight, so that Sunday starts at 1:00.
        let calendar = try calendar(firstWeekday: 1, zone: zone)
        let saturday = try session(at: date(year, month, day + 6, 23, 0, in: calendar), minutes: 15)
        let days = PracticeDay.group([saturday], in: calendar)

        let week = PracticeWeek(containing: try date(year, month, day, 12, 0, in: calendar), days: days, in: calendar)

        let starts = try (0..<7).map { try date(year, month, day + $0, 0, 0, in: calendar) }
        #expect(week.days.map(\.start) == starts)
        #expect(week.days.map(\.total) == [0, 0, 0, 0, 0, 0, 15 * 60])
    }

    private func calendar(firstWeekday: Int, zone: String = "America/Los_Angeles") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar)
        throws -> Date
    {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func session(at start: Date, minutes: Double) throws -> PracticeSession {
        var session = PracticeSession(startedAt: start)
        try session.stop(at: start + minutes * 60)
        return session
    }
}
