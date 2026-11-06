import Foundation
import Testing

@testable import PianismCore

struct WeeklyGoalTests {
    /// A 10-minute session at noon on each of these days after Monday, January 4, 2027, with Monday first in the week.
    private func days(after offsets: [Int]) throws -> [PracticeDay] {
        let calendar = try utcCalendar()
        let monday = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 12)))
        let sessions = try offsets.map { offset in
            let start = try #require(calendar.date(byAdding: .day, value: offset, to: monday))
            var session = PracticeSession(startedAt: start)
            try session.stop(at: start + 600)
            return session
        }
        return PracticeDay.group(sessions, in: calendar)
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func now(after offset: Int) throws -> Date {
        let calendar = try utcCalendar()
        let monday = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 18)))
        return try #require(calendar.date(byAdding: .day, value: offset, to: monday))
    }

    @Test("HIS-3: a week meets the goal with practice on that many days, and not on one fewer")
    func aWeekMeetsTheGoalAtExactlyThatManyDays() throws {
        let calendar = try utcCalendar()
        // Three days in the first week, two in the second.
        let days = try days(after: [0, 2, 4, 7, 9])
        let now = try now(after: 13)

        #expect(WeeklyGoal(days: 3).weeksMet(in: days, at: now, calendar: calendar) == 1)
        #expect(WeeklyGoal(days: 2).weeksMet(in: days, at: now, calendar: calendar) == 2)
        #expect(WeeklyGoal(days: 4).weeksMet(in: days, at: now, calendar: calendar) == 0)
    }

    @Test("HIS-3: this week counts as soon as it meets the goal")
    func thisWeekCountsOnceMet() throws {
        let calendar = try utcCalendar()
        let days = try days(after: [0, 1, 2])

        #expect(WeeklyGoal(days: 3).weeksMet(in: days, at: try now(after: 2), calendar: calendar) == 1)
    }

    @Test("HIS-3: the count covers 52 weeks up to now, and an older week ages out")
    func anOldWeekAgesOut() throws {
        let calendar = try utcCalendar()
        let days = try days(after: [0])
        let goal = WeeklyGoal(days: 1)

        // In its 52nd week it's still counted, and in the 53rd it isn't.
        #expect(goal.weeksMet(in: days, at: try now(after: 51 * 7), calendar: calendar) == 1)
        #expect(goal.weeksMet(in: days, at: try now(after: 52 * 7), calendar: calendar) == 0)
    }

    @Test("HIS-3: nothing resets at the new year, as the count isn't by calendar year")
    func theNewYearResetsNothing() throws {
        let calendar = try utcCalendar()
        // Practice in December 2027, then a look on New Year's Day 2028, a Saturday.
        let days = try days(after: [357])
        let newYear = try #require(calendar.date(from: DateComponents(year: 2028, month: 1, day: 1, hour: 9)))

        #expect(WeeklyGoal(days: 1).weeksMet(in: days, at: newYear, calendar: calendar) == 1)
    }

    @Test("HIS-3: with no minimum, a week's days practiced are those with a row, and a day counts once")
    func daysPracticedMatchTheRows() throws {
        let calendar = try utcCalendar()
        // Two sessions on one day, and one on another.
        let days = try days(after: [0, 0, 3])
        let goal = WeeklyGoal()

        let week = PracticeWeek(containing: try now(after: 0), days: days, in: calendar)

        #expect(goal.daysPracticed(in: week) == 2)
        let nextWeek = PracticeWeek(containing: try now(after: 7), days: days, in: calendar)
        #expect(goal.daysPracticed(in: nextWeek) == 0)
    }

    @Test("HIS-3: a minimum counts a day's whole total, across its sessions, from exactly that much")
    func aMinimumCountsTheDaysTotal() throws {
        let calendar = try utcCalendar()
        // 20 minutes on Monday from two sessions, and 10 on Thursday.
        let days = try days(after: [0, 0, 3])
        let week = PracticeWeek(containing: try now(after: 0), days: days, in: calendar)

        #expect(WeeklyGoal(minimum: 10 * 60).daysPracticed(in: week) == 2)
        #expect(WeeklyGoal(minimum: 15 * 60).daysPracticed(in: week) == 1)
        #expect(WeeklyGoal(minimum: 20 * 60).daysPracticed(in: week) == 1)
        #expect(WeeklyGoal(minimum: 21 * 60).daysPracticed(in: week) == 0)
    }

    @Test("HIS-3: a day short of the minimum doesn't count toward the week's goal")
    func aShortDayDoesntMeetTheGoal() throws {
        let calendar = try utcCalendar()
        let days = try days(after: [0, 0, 3])
        let now = try now(after: 6)

        #expect(WeeklyGoal(days: 2, minimum: 10 * 60).weeksMet(in: days, at: now, calendar: calendar) == 1)
        #expect(WeeklyGoal(days: 2, minimum: 15 * 60).weeksMet(in: days, at: now, calendar: calendar) == 0)
    }

    @Test("HIS-3: the goal starts at three days, with any practice counting")
    func theDefaults() {
        #expect(WeeklyGoal().days == 3)
        #expect(WeeklyGoal().minimum == 0)
        let none: TimeInterval = 0
        let threeHours: TimeInterval = 3 * 60 * 60
        #expect(WeeklyGoal.minimumChoices.first == none)
        #expect(WeeklyGoal.minimumChoices.last == threeHours)
    }
}
