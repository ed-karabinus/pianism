import Foundation
import Testing

@testable import PianismCore

struct PracticeTotalsTests {
    let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        self.calendar = calendar
    }

    @Test("GLN-2: the totals of the day now falls in are that day's finished practice, or 0 with none")
    func totalsAreTodaysFinishedPractice() throws {
        let yesterday = try session(at: date(2026, 10, 14, 9, 0), minutes: 20)
        let today = try session(at: date(2026, 10, 15, 8, 0), minutes: 30)
        let days = PracticeDay.group([yesterday, today], in: calendar)
        let now = try date(2026, 10, 15, 20, 0)

        #expect(
            PracticeTotals(from: days, at: now, in: calendar)
                == PracticeTotals(day: try date(2026, 10, 15, 0, 0), finished: 30 * 60))
        #expect(
            PracticeTotals(from: days, at: try date(2026, 10, 16, 0, 0), in: calendar)
                == PracticeTotals(day: try date(2026, 10, 16, 0, 0), finished: 0))
    }

    @Test("GLN-2: today's practice adds the running session's practice so far, pauses excluded")
    func runningSessionCounts() throws {
        let totals = PracticeTotals(day: try date(2026, 10, 15, 0, 0), finished: 30 * 60)
        var running = PracticeSession(startedAt: try date(2026, 10, 15, 19, 0))
        try running.pause(at: try date(2026, 10, 15, 19, 10))
        try running.resume(at: try date(2026, 10, 15, 19, 15))

        #expect(totals.today(at: try date(2026, 10, 15, 19, 30), running: running, in: calendar) == 55 * 60)
        #expect(totals.today(at: try date(2026, 10, 15, 19, 30), running: nil, in: calendar) == 30 * 60)
    }

    @Test("GLN-2: past midnight, yesterday's totals and a session still running from yesterday count for 0")
    func midnightStartsOver() throws {
        let totals = PracticeTotals(day: try date(2026, 10, 14, 0, 0), finished: 30 * 60)
        let fromYesterday = PracticeSession(startedAt: try date(2026, 10, 14, 23, 30))

        #expect(totals.today(at: try date(2026, 10, 14, 23, 59), running: fromYesterday, in: calendar) == 59 * 60)
        #expect(totals.today(at: try date(2026, 10, 15, 0, 0), running: fromYesterday, in: calendar) == 0)
        #expect(totals.today(at: try date(2026, 10, 15, 0, 30), running: nil, in: calendar) == 0)
    }

    @Test("GLN-2, ADR 0004: a finished session that ran past midnight counts toward the day it started")
    func sessionPastMidnightCountsTowardItsStartDay() throws {
        let late = try session(at: date(2026, 10, 14, 23, 30), minutes: 60)
        let days = PracticeDay.group([late], in: calendar)

        #expect(PracticeTotals(from: days, at: try date(2026, 10, 14, 23, 45), in: calendar).finished == 60 * 60)
        #expect(PracticeTotals(from: days, at: try date(2026, 10, 15, 0, 45), in: calendar).finished == 0)
    }

    @Test("GLN-2: a session that has ended isn't counted until history has it, so it's never counted twice")
    func endedSessionWaitsForHistory() throws {
        let totals = PracticeTotals(day: try date(2026, 10, 15, 0, 0), finished: 30 * 60)
        let ended = try session(at: date(2026, 10, 15, 19, 0), minutes: 10)

        #expect(totals.today(at: try date(2026, 10, 15, 19, 30), running: ended, in: calendar) == 30 * 60)
    }

    @Test(
        "GLN-2: on days of 23 and 25 hours, when daylight saving starts or ends, the day's practice still counts",
        arguments: [(2027, 3, 14), (2027, 11, 7)])
    func daylightSavingDays(year: Int, month: Int, day: Int) throws {
        let early = try session(at: date(year, month, day, 0, 30), minutes: 20)
        let days = PracticeDay.group([early], in: calendar)
        let totals = PracticeTotals(from: days, at: try date(year, month, day, 12, 0), in: calendar)
        let running = PracticeSession(startedAt: try date(year, month, day, 23, 0))

        #expect(totals.day == (try date(year, month, day, 0, 0)))
        #expect(totals.today(at: try date(year, month, day, 23, 30), running: running, in: calendar) == 50 * 60)
        #expect(totals.today(at: try date(year, month, day + 1, 0, 30), running: running, in: calendar) == 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func session(at start: Date, minutes: Double) throws -> PracticeSession {
        var session = PracticeSession(startedAt: start)
        try session.stop(at: start + minutes * 60)
        return session
    }
}
