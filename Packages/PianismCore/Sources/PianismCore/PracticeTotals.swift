import Foundation

/// A day's finished practice, which the app works out and the widget shows (GLN-2, ADR 0010).
public struct PracticeTotals: Sendable, Hashable, Codable {
    /// The day's first moment, in the calendar the app grouped sessions by when it wrote this.
    public let day: Date
    /// Practice time of the sessions that started that day and have ended, excluding pauses (SES-2).
    public let finished: TimeInterval

    public init(day: Date, finished: TimeInterval) {
        self.day = day
        self.finished = finished
    }

    /// The totals of the day `now` falls in, from `days` as History groups them.
    public init(from days: [PracticeDay], at now: Date, in calendar: Calendar) {
        let today = days.first { calendar.isDate($0.start, inSameDayAs: now) }
        self.init(day: calendar.startOfDay(for: now), finished: today?.total ?? 0)
    }

    /// Today's finished practice at `now`: the finished total if it's for `now`'s day, else 0, as past midnight a new
    /// day starts with none. The widget counts the running session on top itself.
    public func today(at now: Date, in calendar: Calendar) -> TimeInterval {
        calendar.isDate(day, inSameDayAs: now) ? finished : 0
    }
}
