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
        // Typed outside the macro, as Xcode 26.6 (CI's Mac) gives up working it out inside.
        let totals: [TimeInterval] = [45 * 60, 20 * 60]
        #expect(days.map(\.total) == totals)
    }

    @Test("HIS-1: a day's total adds the whole seconds its rows show, so a row's fraction can't make them disagree")
    func totalAddsWholeSeconds() throws {
        let calendar = try calendar("America/Los_Angeles")
        let start = try date(2026, 11, 4, 15, 0, in: calendar)
        var sessions: [PracticeSession] = []
        // As the owner saw on 2026-11-04: rows of 1:33, 2:35 and 1:01 under a total of 5:11 rather than 5:09.
        for (minute, played) in [(0, 93.4), (10, 155.9), (20, 61.9)] {
            var session = PracticeSession(startedAt: start + Double(minute) * 60)
            try session.stop(at: session.startedAt + played)
            sessions.append(session)
        }

        #expect(PracticeDay.group(sessions, in: calendar).map(\.total) == [5 * 60 + 9])
    }

    @Test("HIS-1: a session across midnight shows under both days, each with its minutes, and totals add the rows")
    func acrossMidnightShowsOnBothDays() throws {
        let calendar = try calendar("America/Los_Angeles")
        let start = try date(2026, 10, 14, 23, 30, in: calendar)
        let midnight = try date(2026, 10, 15, 0, 0, in: calendar)
        let late = try session(at: start, minutes: 60)

        let days = PracticeDay.group([late], in: calendar)

        let starts = [midnight, try date(2026, 10, 14, 0, 0, in: calendar)]
        let totals: [TimeInterval] = [1_800, 1_800]
        #expect(days.map(\.start) == starts)
        #expect(days.map(\.sessions) == [[late], [late]])
        #expect(days.map(\.total) == totals)
        #expect(days[0].part(of: late).span == midnight..<(midnight + 1_800))
        #expect(days[1].part(of: late).span == start..<midnight)
    }

    @Test("HIS-1: a session over several midnights shows on each day with practice, and not on a day it paused through")
    func overSeveralMidnights() throws {
        let calendar = try calendar("America/Los_Angeles")
        let monday = try date(2026, 10, 12, 22, 0, in: calendar)
        let wednesday = try date(2026, 10, 14, 6, 0, in: calendar)
        let wednesdayStart = try date(2026, 10, 14, 0, 0, in: calendar)
        let tuesdayStart = try date(2026, 10, 13, 0, 0, in: calendar)
        let mondayStart = try date(2026, 10, 12, 0, 0, in: calendar)

        var straight = PracticeSession(startedAt: monday)
        try straight.stop(at: wednesday)
        let straightDays = PracticeDay.group([straight], in: calendar).map(\.start)
        #expect(straightDays == [wednesdayStart, tuesdayStart, mondayStart])
        let straightTotals: [TimeInterval] = [21_600, 86_400, 7_200]
        #expect(PracticeDay.group([straight], in: calendar).map(\.total) == straightTotals)

        var paused = PracticeSession(startedAt: monday)
        try paused.pause(at: monday + 3_600)
        try paused.resume(at: wednesday)
        try paused.stop(at: wednesday + 3_600)
        let pausedDays = PracticeDay.group([paused], in: calendar)
        #expect(pausedDays.map(\.start) == [wednesdayStart, mondayStart])
        let pausedTotals: [TimeInterval] = [3_600, 3_600]
        #expect(pausedDays.map(\.total) == pausedTotals)
    }

    @Test("HIS-1: each row rounds down on its own, so a day's total equals its rows, a second under the whole session")
    func eachRowRoundsDownOnItsOwn() throws {
        let calendar = try calendar("America/Los_Angeles")
        let midnight = try date(2026, 10, 15, 0, 0, in: calendar)
        var session = PracticeSession(startedAt: midnight - 2_399.6)
        try session.stop(at: midnight + 1_199.6)

        let days = PracticeDay.group([session], in: calendar)

        let totals: [TimeInterval] = [1_199, 2_399]
        #expect(days.map(\.total) == totals)
        #expect(session.elapsed(at: midnight).rounded(.down) == 3_599)
    }

    @Test(
        "HIS-1: a part needs a whole second to get a row, so one ending exactly at midnight stays on one day",
        arguments: [(0.0, 1), (0.5, 1), (1.0, 2)])
    func aPartNeedsAWholeSecond(pastMidnight: TimeInterval, rows: Int) throws {
        let calendar = try calendar("America/Los_Angeles")
        let midnight = try date(2026, 10, 15, 0, 0, in: calendar)
        var session = PracticeSession(startedAt: midnight - 60)
        try session.stop(at: midnight + pastMidnight)

        #expect(PracticeDay.group([session], in: calendar).count == rows)
    }

    @Test("HIS-1: a session with no whole second on any day stays on the day it started, so it can still be deleted")
    func noWholeSecondStaysOnItsFirstDay() throws {
        let calendar = try calendar("America/Los_Angeles")
        let midnight = try date(2026, 10, 15, 0, 0, in: calendar)
        var session = PracticeSession(startedAt: midnight - 0.4)
        try session.stop(at: midnight + 0.4)

        let days = PracticeDay.group([session], in: calendar)

        #expect(days.map(\.start) == [try date(2026, 10, 14, 0, 0, in: calendar)])
        #expect(days.map(\.sessions) == [[session]])
        #expect(days[0].total == 0)
    }

    @Test("HIS-1: where the clocks skip midnight, the split is at the day's first moment")
    func whereTheClocksSkipMidnight() throws {
        let santiago = try calendar("America/Santiago")
        let late = try session(at: date(2027, 9, 4, 23, 30, in: santiago), minutes: 60)

        let days = PracticeDay.group([late], in: santiago)

        #expect(days.first?.start == (try date(2027, 9, 5, 1, 0, in: santiago)))
        let totals: [TimeInterval] = [1_800, 1_800]
        #expect(days.map(\.total) == totals)
    }

    @Test("HIS-1: on a day of 25 hours, the split comes after all 25")
    func onALongDay() throws {
        let calendar = try calendar("America/Los_Angeles")
        let long = try session(at: date(2027, 11, 7, 0, 30, in: calendar), minutes: 1_500)

        let days = PracticeDay.group([long], in: calendar)

        let totals: [TimeInterval] = [1_800, 88_200]
        #expect(days.map(\.total) == totals)
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
