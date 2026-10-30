import Foundation

/// One week of practice at a glance (HIS-2): its seven days, oldest first, each with its total, and the week's
/// total.
public struct PracticeWeek: Sendable {
    /// The week's seven days, oldest first, including days without practice.
    public let days: [PracticeDay]
    /// Practice time of all the week's sessions, excluding pauses (SES-2).
    public var total: TimeInterval { days.reduce(0) { $0 + $1.total } }

    /// The week holding `date`, on the calendar's first weekday, from `days` as ``PracticeDay/group(_:in:)`` makes
    /// them. Days are found by date, not by counting hours, so a week with a daylight-saving change still has seven.
    public init(containing date: Date, days: [PracticeDay], in calendar: Calendar) {
        // Can't fail: every date falls in some week.
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let byStart = Dictionary(days.map { ($0.start, $0) }) { first, _ in first }
        self.days = (0..<7).map { offset in
            // Where the clocks change at midnight, as in Santiago, a day starts at 1:00, as `group` keys it.
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start) ?? start)
            return byStart[day] ?? PracticeDay(start: day, sessions: [], total: 0)
        }
    }
}
