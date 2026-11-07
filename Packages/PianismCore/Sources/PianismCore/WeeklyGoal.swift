import Foundation

/// How many days a week someone means to practice, and how much makes a day count (HIS-3). A minimum lets someone
/// decide that 10 minutes is a good day, or that it takes 2 hours (decided with Ed, 2026-11-06).
public struct WeeklyGoal: Sendable, Hashable {
    /// Three days, from the spec.
    public static let defaultDays = 3
    /// The minimums to pick from, up to 3 hours. Any practice at all is a minimum of zero.
    public static let minimumChoices: [TimeInterval] = [10, 15, 30, 45, 60, 90, 120, 180].map { $0 * 60 }

    public var days: Int
    /// A day's least practice to count. At zero, any row in History counts, so the count matches the chart's bars.
    public var minimum: TimeInterval

    public init(days: Int = defaultDays, minimum: TimeInterval = 0) {
        self.days = days
        self.minimum = minimum
    }

    /// How many of the week's days have enough practice to count.
    public func daysPracticed(in week: PracticeWeek) -> Int {
        week.days.count(where: counts)
    }

    /// How many of the past year's weeks met the goal, counting this week as soon as it does. Over the 52 weeks up to
    /// now rather than the calendar year, so it never drops to zero on January 1, as nothing may reset (decided with
    /// Ed, 2026-11-06). `days` are as ``PracticeDay/group(_:in:)`` makes them.
    public func weeksMet(in days: [PracticeDay], at now: Date, calendar: Calendar) -> Int {
        // Can't fail: every date falls in some week, with another 51 before it.
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let oldest = calendar.date(byAdding: .weekOfYear, value: -51, to: thisWeek) ?? thisWeek
        let byWeek = Dictionary(grouping: days.filter(counts)) {
            calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start ?? $0.start
        }
        return byWeek.count { week, counted in week >= oldest && counted.count >= self.days }
    }

    private func counts(_ day: PracticeDay) -> Bool {
        !day.sessions.isEmpty && day.total >= minimum
    }
}
