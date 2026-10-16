import Foundation

/// One day in the history list (HIS-1): the sessions that started that day, newest first, and the
/// day's total practice time.
public struct PracticeDay: Sendable, Hashable, Identifiable {
    /// The day's first moment, in the calendar the sessions were grouped by.
    public let start: Date
    public let sessions: [PracticeSession]
    /// Practice time of all the day's sessions, excluding pauses (SES-2).
    public let total: TimeInterval

    public var id: Date { start }

    /// Groups finished sessions by the day each one started, newest day first. A session that runs
    /// past midnight counts toward the day it started (ADR 0004).
    public static func group(_ sessions: some Sequence<PracticeSession>, in calendar: Calendar) -> [PracticeDay] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
            .map { start, sessions in
                // Sessions starting at the same instant have no promised order, so `>=` would do as well.
                let newestFirst = sessions.sorted { $0.startedAt > $1.startedAt }  // mutate:ignore - only ties differ
                // An ended session's practice time is fixed, so the date passed here is ignored.
                let total = newestFirst.reduce(0) { $0 + $1.elapsed(at: .distantPast) }
                return PracticeDay(start: start, sessions: newestFirst, total: total)
            }
            .sorted { $0.start > $1.start }  // mutate:ignore - days never tie: there is one per date
    }
}
