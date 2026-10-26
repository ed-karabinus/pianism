import Foundation

/// Turns a connected piano's notes into changes to a MIDI session (MIDI-1): three notes within 10 s start one
/// at the first of them. A silence pauses it at its last note, and a note resumes it. A longer silence ends it
/// 5 s after its last note, and so does Stop, unless tapped sooner (MIDI-R4).
///
/// It reads no clock and stores nothing. Each event carries its date, each effect is dated for
/// ``SessionRecorder`` to store, and ``sync(with:)`` puts it back where the stored session says after any
/// other change, such as a tapped Pause or a relaunch.
public struct MIDIDetector: Sendable {
    public enum Event: Sendable {
        /// A key struck, with a velocity above zero. A chord is one per key, at one date.
        case noteOn(Date)
        /// The time now, so a silence that has lasted long enough pauses or ends the session.
        case tick(Date)
        /// Stop, tapped on a MIDI session.
        case stop(Date)
    }

    public enum Effect: Sendable, Equatable {
        /// Start a MIDI session at the first note of the three.
        case start(at: Date)
        /// Pause the session at its last note, after a silence.
        case pause(at: Date)
        /// Resume the session at a note.
        case resume(at: Date)
        /// Pause the session at its last note if it's running, so the time after it isn't played time, then end it.
        case end(afterLastNote: Date, at: Date)
    }

    private enum State {
        /// No MIDI session is going. Holds the notes that could still count toward a start.
        case idle(recent: [Date])
        case playing(lastNote: Date)
        /// Paused at `since`: its last note after a silence, or when Pause was tapped.
        case paused(since: Date, bySilence: Bool)
    }

    private static let startThreshold = 3
    private static let startWindow: TimeInterval = 10
    private static let endTail: TimeInterval = 5

    private let settings: MIDISettings
    private var state = State.idle(recent: [])

    public init(_ settings: MIDISettings = .init()) {
        self.settings = settings
    }

    /// When the silence so far pauses or ends the session, if nothing is played first.
    public var nextDeadline: Date? {
        switch state {
        case .idle: nil
        case .playing(let last): last + settings.pauseAfter
        case .paused(let since, _): since + settings.saveAfter
        }
    }

    /// The last note of the session being played, if it's playing.
    public var lastNote: Date? {
        if case .playing(let last) = state { last } else { nil }
    }

    /// Whether the session paused itself after a silence, rather than at a tap.
    public var isPausedBySilence: Bool {
        if case .paused(_, true) = state { true } else { false }
    }

    /// The changes `event` makes to the MIDI session, which the caller stores in order. A note first applies the
    /// silence before it, so one that arrives late, as after the app was away, can't fill that silence.
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .noteOn(let date): expire(at: date) + count(date)
        case .tick(let date): expire(at: date)
        case .stop(let date): stop(at: date)
        }
    }

    /// Pauses or ends the session if the silence up to `now` is long enough. Compared as `nextDeadline` is, so a
    /// tick at the deadline acts.
    private mutating func expire(at now: Date) -> [Effect] {
        switch state {
        case .idle:
            return []
        case .playing(let last) where now >= last + settings.saveAfter,
            .paused(let last, _) where now >= last + settings.saveAfter:
            state = .idle(recent: [])
            return [.end(afterLastNote: last, at: last + Self.endTail)]
        case .playing(let last) where now >= last + settings.pauseAfter:
            state = .paused(since: last, bySilence: true)
            return [.pause(at: last)]
        case .playing, .paused:
            return []
        }
    }

    private mutating func count(_ date: Date) -> [Effect] {
        switch state {
        case .idle(let recent):
            // Notes dated after this one, as before the clock stepped back, can't start a session in the future.
            let window = recent.filter { (0..<Self.startWindow).contains(date.timeIntervalSince($0)) } + [date]
            guard window.count >= Self.startThreshold, let first = window.min() else {
                state = .idle(recent: window)
                return []
            }
            state = .playing(lastNote: date)
            return [.start(at: first)]
        case .playing(let last):
            state = .playing(lastNote: max(last, date))
            return []
        case .paused(let since, _):
            // A note dated before the pause, as after the clock stepped back, resumes at the pause.
            let resumed = max(date, since)
            state = .playing(lastNote: resumed)
            return [.resume(at: resumed)]
        }
    }

    private mutating func stop(at date: Date) -> [Effect] {
        switch state {
        case .idle:
            return []
        case .playing(let last), .paused(let last, _):
            state = .idle(recent: [])
            return [.end(afterLastNote: last, at: min(date, last + Self.endTail))]
        }
    }

    /// Follows the stored session. A paused MIDI session is paused since its last change, which a tapped Pause
    /// made unless this detector paused it. A running one is playing from its last change, its stored last note or
    /// the last note heard, whichever is latest, which keeps the notes since a pause the store refused, or since
    /// the last change before the app was killed while away. Anything else is idle: an ended
    /// MIDI session, which history couldn't take, too, as nothing can change it.
    public mutating func sync(with session: PracticeSession?) {
        guard let session, session.source == .midi, session.state != .ended else {
            if case .idle = state { return }
            state = .idle(recent: [])
            return
        }
        let stored = max(session.latestEvent, session.lastNoteAt ?? .distantPast)
        switch (state, session.state) {
        case (.paused(let since, let bySilence), .paused):
            state = .paused(since: session.latestEvent, bySilence: bySilence && since == session.latestEvent)
        case (_, .paused):
            state = .paused(since: session.latestEvent, bySilence: false)
        case (.playing(let last), _), (.paused(let last, _), _):
            state = .playing(lastNote: max(last, stored))
        case (.idle, _):
            state = .playing(lastNote: stored)
        }
    }
}
