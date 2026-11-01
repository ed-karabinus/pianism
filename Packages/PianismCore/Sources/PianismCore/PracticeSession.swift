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

    /// How a session was recorded (SES-5).
    public enum Source: String, Sendable, Hashable, Codable {
        /// Timed as it happened, from Start to Stop.
        case timer
        /// Added after the fact, from History.
        case manual
        /// Started by a connected piano's notes (MIDI-1).
        case midi
    }

    public let id: UUID
    public private(set) var startedAt: Date
    /// Where the session started, kept so the day it was practiced can be recovered wherever it's
    /// viewed later (ADR 0006). `nil` for a session started before this was recorded.
    public let timeZone: TimeZone?
    public private(set) var pauses: [Pause] = []
    public private(set) var endedAt: Date?
    /// When a running MIDI session's last note was played, stored as the app leaves the screen, so a kill while
    /// it's away doesn't lose the notes since the last change (MIDI-1). `nil` once it ends, so history never has it.
    public private(set) var lastNoteAt: Date?
    /// The pieces and skills practiced, in the order they were added (TAG-2). A session with none is
    /// valid, and shows as "Untagged".
    public var tagIDs: [Tag.ID] { tags ?? [] }
    /// Optional, so sessions written before tags existed still decode (ADR 0003), and `nil` rather than
    /// empty, so an untagged session equals itself after a round trip through history.
    private var tags: [Tag.ID]?
    /// What the user wrote about the session (SES-5). Empty when there's none.
    public var note: String { notes ?? "" }
    /// Optional and `nil` when empty, for the same reasons as `tags`.
    private var notes: String?
    /// Timed, unless the session was added after the fact.
    public var source: Source { recordedAs ?? .timer }
    /// Optional and `nil` for a timed session, for the same reasons as `tags`.
    private let recordedAs: Source?

    /// Starts a new, running session (SES-1); `source` records how it is being made (SES-5).
    public init(id: UUID = UUID(), startedAt: Date, timeZone: TimeZone? = nil, source: Source = .timer) {
        self.id = id
        self.startedAt = startedAt
        self.timeZone = timeZone
        recordedAs = source == .timer ? nil : source
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

    /// The moment a clock counting only practice would have started, so `now - practiceOrigin` is the practice so
    /// far while the session runs, and a clock stopped at the pause, or at the end, reads the same (GLN-2). Later
    /// than `startedAt` by the pauses so far (SES-2).
    public var practiceOrigin: Date {
        let at = endedAt ?? latestEvent
        return at.addingTimeInterval(-elapsed(at: at))
    }

    /// When a running session's practice time reaches `practice`, if it keeps running, or `nil` if it's paused
    /// or ended (SES-4). A moment in the past means it already has. One already past it when it last resumed, as
    /// when Pause came after the cap but before the app noticed, reaches it then, so it can still stop there.
    public func whenPracticeReaches(_ practice: TimeInterval) -> Date? {
        guard state == .running else { return nil }
        return max(latestEvent.addingTimeInterval(practice - elapsed(at: latestEvent)), latestEvent)
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
        lastNoteAt = nil
    }

    /// Records when a running MIDI session's last note was played (MIDI-1).
    public mutating func noteLastPlayed(at date: Date) throws(SessionError) {
        try checkCanChange(at: date)
        lastNoteAt = date
    }

    /// Replaces the session's tags (TAG-2). A finished session's tags change through ``editTags(_:)``.
    public mutating func setTags(_ ids: [Tag.ID]) throws(SessionError) {
        guard state != .ended else { throw .alreadyEnded }
        tags = ids.isEmpty ? nil : ids
    }

    /// Replaces a finished session's tags, when the user edits it (SES-5).
    public mutating func editTags(_ ids: [Tag.ID]) throws(SessionError) {
        guard state == .ended else { throw .notEnded }
        tags = ids.isEmpty ? nil : ids
    }

    /// Moves a finished session's start and end, when the user edits it (SES-5). Pauses keep their times:
    /// a pause outside the new span is dropped, and one across its start or end is cut there.
    public mutating func editTimes(start: Date, end: Date) throws(SessionError) {
        guard state == .ended else { throw .notEnded }
        guard end >= start else { throw .timeWentBackwards }
        pauses = pauses.compactMap { pause in
            let from = max(pause.start, start)
            let to = min(pause.end ?? end, end)
            return from < to ? Pause(start: from, end: to) : nil
        }
        startedAt = start
        endedAt = end
    }

    /// Replaces a finished session's note, when the user edits it (SES-5).
    public mutating func editNote(_ text: String) throws(SessionError) {
        guard state == .ended else { throw .notEnded }
        notes = text.isEmpty ? nil : text
    }

    /// The practice time this finished session shares with `other`, which a day's total counts twice
    /// (SES-5). Pauses aren't practice, so time in either's pause isn't shared. Zero if either is running.
    public func sharedPractice(with other: PracticeSession) -> TimeInterval {
        practiceSpans.flatMap { span in other.practiceSpans.map(span.clamped) }
            .reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
    }

    /// When a finished session was practising: from its start to the first pause, between pauses, and
    /// from the last pause to its end. Empty while it's running.
    private var practiceSpans: [Range<Date>] {
        guard let end = endedAt else { return [] }
        let starts = [startedAt] + pauses.map { $0.end ?? end }
        let ends = pauses.map(\.start) + [end]
        // The check only stops a malformed pause from trapping in `..<`.
        return zip(starts, ends).compactMap { $0 < $1 ? $0..<$1 : nil }  // mutate:ignore - empty spans share nothing
    }

    /// The most recent moment anything happened to this session: its start, or its last pause or resume.
    public var latestEvent: Date {
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
    /// A change, other than an edit, to a session that has ended.
    case alreadyEnded
    /// An edit to a session that hasn't ended. Running sessions change only as they happen.
    case notEnded
    /// A change dated before something that already happened to the session, or an edit that ends a
    /// session before it starts.
    case timeWentBackwards
}
