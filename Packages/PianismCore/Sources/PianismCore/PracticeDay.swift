import Foundation

/// One day in the history list (HIS-1): the sessions with practice that day, newest first, and the day's total
/// practice time. A session across midnight is listed on each day it has practice in, with that day's minutes
/// (decided with Ed, 2026-11-04; ADR 0004).
public struct PracticeDay: Sendable, Hashable, Identifiable {
    /// The day's first moment, in the calendar the sessions were grouped by.
    public let start: Date
    /// The next day's first moment.
    public let end: Date
    public let sessions: [PracticeSession]

    public var id: Date { start }

    /// Practice time of the day's rows, excluding pauses (SES-2), so it always equals what they add up to (decided
    /// with Ed, 2026-11-04).
    public var total: TimeInterval { sessions.reduce(0) { $0 + part(of: $1).practiced } }

    /// A session's share of this day, which its row shows.
    public struct Part: Sendable, Hashable {
        /// When the session ran within the day.
        public let span: Range<Date>
        /// Its practice within the day, in the whole seconds a row shows, rounded down as the clock is. So two rows
        /// of one session can add to a second less than the session. It keeps its exact times.
        public let practiced: TimeInterval
    }

    public func part(of session: PracticeSession) -> Part {
        let from = max(session.startedAt, start)
        return Part(
            span: from..<max(from, min(session.endedAt ?? end, end)),
            practiced: session.practiced(from: start, before: end).rounded(.down))
    }

    init(start: Date, sessions: [PracticeSession] = [], in calendar: Calendar) {
        self.start = start
        end = Self.day(after: start, in: calendar)
        self.sessions = sessions
    }

    /// Groups finished sessions by the days they have practice in, newest day first.
    public static func group(_ sessions: some Sequence<PracticeSession>, in calendar: Calendar) -> [PracticeDay] {
        var byDay: [Date: [PracticeSession]] = [:]
        for session in sessions {
            for day in session.days(in: calendar) { byDay[day, default: []].append(session) }
        }
        return byDay.map { start, sessions in
            // Sessions starting at the same instant have no promised order, so `>=` would do as well.
            let newestFirst = sessions.sorted { $0.startedAt > $1.startedAt }  // mutate:ignore - only ties differ
            return PracticeDay(start: start, sessions: newestFirst, in: calendar)
        }
        .sorted { $0.start > $1.start }  // mutate:ignore - days never tie: there is one per date
    }

    /// The first moment of the day after `day`. By date, not by counting hours, for days of 23 and 25 hours. Where the
    /// clocks change at midnight, as in Santiago, a day starts at 1:00.
    fileprivate static func day(after day: Date, in calendar: Calendar) -> Date {
        // Can't fail: every date has a next day.
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400))
    }
}

extension PracticeSession {
    /// The first moments of the days History lists this session on: each with at least a whole second of its practice,
    /// which is the least a row can show. A pause across a whole day leaves that day out. A session with no whole
    /// second on any day stays on the day it started, or it couldn't be seen, edited or deleted.
    public func days(in calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: startedAt)
        var days: [Date] = []
        var day = first
        while day <= endedAt ?? startedAt {  // mutate:ignore - a day starting at the very end has no practice in it
            let next = PracticeDay.day(after: day, in: calendar)
            if practiced(from: day, before: next) >= 1 { days.append(day) }
            day = next
        }
        return days.isEmpty ? [first] : days
    }
}
