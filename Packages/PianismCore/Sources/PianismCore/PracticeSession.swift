import Foundation

/// One practice session: when it started, when it was paused, and when it ended.
///
/// Elapsed time is always derived from these timestamps, never kept as a running counter,
/// so a session restored after the app was killed still shows the right time (SES-6).
/// Every change takes the time it happens at, so callers pass `clock.now` (principle E3).
public struct PracticeSession: Sendable, Hashable, Codable, Identifiable {
    /// A span of time that doesn't count as practice.
    public struct Pause: Sendable, Hashable, Codable {
        public let start: Date
        /// `nil` while the pause is still going on.
        public fileprivate(set) var end: Date?
    }

    public enum State: Sendable, Hashable {
        case running
        case paused
        case ended
    }

    public let id: UUID
    public let startedAt: Date
    /// Where the session started, kept so the day it was practiced can be recovered wherever it's
    /// viewed later (ADR 0006). `nil` for a session started before this was recorded.
    public let timeZone: TimeZone?
    public private(set) var pauses: [Pause] = []
    public private(set) var endedAt: Date?

    /// Starts a new, running session (SES-1).
    public init(id: UUID = UUID(), startedAt: Date, timeZone: TimeZone? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.timeZone = timeZone
    }

    public var state: State {
        if endedAt != nil { return .ended }
        if let last = pauses.last, last.end == nil { return .paused }
        return .running
    }

    /// Practice time up to `now`, excluding pauses (SES-2).
    ///
    /// For an ended session the result is fixed and `now` is ignored.
    public func elapsed(at now: Date) -> TimeInterval {
        let end = endedAt ?? max(now, latestEvent)
        let paused = pauses.reduce(0) { total, pause in
            total + (pause.end ?? end).timeIntervalSince(pause.start)
        }
        return end.timeIntervalSince(startedAt) - paused
    }

    /// Pauses a running session. Time from `date` until ``resume(at:)`` doesn't count (SES-2).
    public mutating func pause(at date: Date) throws(SessionError) {
        try checkCanChange(at: date)
        guard state == .running else { throw .alreadyPaused }
        pauses.append(Pause(start: date))
    }

    /// Resumes a paused session (SES-2).
    public mutating func resume(at date: Date) throws(SessionError) {
        try checkCanChange(at: date)
        guard state == .paused else { throw .notPaused }
        pauses[pauses.count - 1].end = date
    }

    /// Ends the session (SES-1). Stopping while paused ends it at `date`, and the
    /// open pause still doesn't count as practice (SES-2).
    public mutating func stop(at date: Date) throws(SessionError) {
        try checkCanChange(at: date)
        if state == .paused {
            pauses[pauses.count - 1].end = date
        }
        endedAt = date
    }

    /// The most recent moment anything happened to this session.
    private var latestEvent: Date {
        guard let last = pauses.last else { return startedAt }
        return last.end ?? last.start
    }

    private func checkCanChange(at date: Date) throws(SessionError) {
        guard state != .ended else { throw .alreadyEnded }
        guard date >= latestEvent else { throw .timeWentBackwards }
    }
}

/// Why a change to a ``PracticeSession`` was rejected.
public enum SessionError: Error, Sendable, Hashable {
    /// `pause` on a session that is already paused.
    case alreadyPaused
    /// `resume` on a session that isn't paused.
    case notPaused
    /// Any change to a session that has ended. Editing finished sessions is SES-5's job.
    case alreadyEnded
    /// A change dated before something that already happened to the session.
    case timeWentBackwards
}
