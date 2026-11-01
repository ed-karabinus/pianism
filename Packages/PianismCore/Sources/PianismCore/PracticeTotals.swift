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

    /// Today's practice at `now`: the finished total if it's for `now`'s day, plus `running`'s practice so far if
    /// it started on that day and hasn't ended. A session counts toward the day it started (ADR 0004), and one that
    /// has ended is counted once history has it.
    public func today(at now: Date, running: PracticeSession?, in calendar: Calendar) -> TimeInterval {
        var total = calendar.isDate(day, inSameDayAs: now) ? finished : 0
        if let running, running.state != .ended, calendar.isDate(running.startedAt, inSameDayAs: now) {
            total += running.elapsed(at: now)
        }
        return total
    }
}
