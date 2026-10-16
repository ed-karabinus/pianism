import Foundation
import Testing

@testable import PianismCore

struct PracticeDayTests {
    @Test("HIS-1: sessions group by the day they started, newest day first, with each day's total")
    func groupsByStartDay() throws {
        let calendar = try calendar("America/Los_Angeles")
        let yesterday = try session(at: date(2026, 10, 14, 9, 0, in: calendar), minutes: 20)
        let morning = try session(at: date(2026, 10, 15, 8, 0, in: calendar), minutes: 30)
        let evening = try session(at: date(2026, 10, 15, 19, 0, in: calendar), minutes: 15)

        let days = PracticeDay.group([yesterday, morning, evening], in: calendar)

        #expect(
            days.map(\.start) == [
                try date(2026, 10, 15, 0, 0, in: calendar), try date(2026, 10, 14, 0, 0, in: calendar),
            ])
        #expect(days.map(\.sessions) == [[evening, morning], [yesterday]])
        #expect(days.map(\.total) == [45 * 60, 20 * 60])
    }

    @Test("HIS-1: a session that runs past midnight counts toward the day it started")
    func lateSessionCountsTowardStartDay() throws {
        let calendar = try calendar("America/Los_Angeles")
        let late = try session(at: date(2026, 10, 14, 23, 30, in: calendar), minutes: 60)

        let days = PracticeDay.group([late], in: calendar)

        #expect(days.map(\.start) == [try date(2026, 10, 14, 0, 0, in: calendar)])
        #expect(days.map(\.total) == [60 * 60])
    }

    @Test("HIS-1, SES-2: paused time doesn't count toward a day's total")
    func pausesDontCount() throws {
        let calendar = try calendar("America/Los_Angeles")
        let paused = try session(at: date(2026, 10, 15, 8, 0, in: calendar), minutes: 30, pausedMinutes: 10)

        #expect(PracticeDay.group([paused], in: calendar).map(\.total) == [30 * 60])
    }

    @Test("HIS-1: the same moment falls on the local day of the calendar's time zone")
    func daysFollowTheTimeZone() throws {
        // 06:00 UTC is 15:00 on the 15th in Tokyo, but 23:00 on the 14th in Los Angeles.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-15T06:00:00Z"))
        let practice = try session(at: instant, minutes: 30)
        let tokyo = try calendar("Asia/Tokyo")
        let losAngeles = try calendar("America/Los_Angeles")

        let tokyoDay = try #require(PracticeDay.group([practice], in: tokyo).first)
        let losAngelesDay = try #require(PracticeDay.group([practice], in: losAngeles).first)

        #expect(tokyoDay.start == (try date(2026, 10, 15, 0, 0, in: tokyo)))
        #expect(losAngelesDay.start == (try date(2026, 10, 14, 0, 0, in: losAngeles)))
    }

    @Test(
        "HIS-1: days of 23 and 25 hours, when daylight saving starts or ends, still group by date",
        arguments: [(2027, 3, 14), (2027, 11, 7)])
    func daylightSavingDays(year: Int, month: Int, day: Int) throws {
        let calendar = try calendar("America/Los_Angeles")
        let early = try session(at: date(year, month, day, 0, 30, in: calendar), minutes: 20)
        let late = try session(at: date(year, month, day, 23, 30, in: calendar), minutes: 20)

        let days = PracticeDay.group([early, late], in: calendar)

        #expect(days.map(\.start) == [try date(year, month, day, 0, 0, in: calendar)])
        #expect(days.map(\.sessions) == [[late, early]])
    }

    @Test("HIS-1: no sessions make no days")
    func empty() throws {
        #expect(PracticeDay.group([], in: try calendar("America/Los_Angeles")).isEmpty)
    }

    private func calendar(_ timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar)
        throws -> Date
    {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    /// An ended session with `minutes` of practice, and an optional pause after its first minute.
    private func session(at start: Date, minutes: Double, pausedMinutes: Double = 0) throws -> PracticeSession {
        var session = PracticeSession(startedAt: start)
        if pausedMinutes > 0 {
            try session.pause(at: start + 60)
            try session.resume(at: start + 60 + pausedMinutes * 60)
        }
        try session.stop(at: start + (minutes + pausedMinutes) * 60)
        return session
    }
}
