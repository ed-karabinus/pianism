import Foundation

/// Turns a connected piano's notes into changes to a MIDI session (MIDI-1): three notes within 10 s start one
/// at the first of them, and Stop ends it at the earlier of the tap and 5 s after its last note (MIDI-R4).
///
/// It reads no clock and stores nothing. Each event carries its date, each effect is dated for
/// ``SessionRecorder`` to store, and ``sync(with:)`` puts it back where the stored session says after any
/// other change, such as a tapped Pause or a relaunch.
public struct MIDIDetector: Sendable {
    public enum Event: Sendable {
        /// A key struck, with a velocity above zero. A chord is one per key, at one date.
        case noteOn(Date)
        /// Stop, tapped on a MIDI session.
        case stop(Date)
    }

    public enum Effect: Sendable, Equatable {
        /// Start a MIDI session at the first note of the three.
        case start(at: Date)
        /// Pause the session at its last note if it's running, so the time after it isn't played time, then end it.
        case end(afterLastNote: Date, at: Date)
    }

    private enum State {
        /// No MIDI session is going. Holds the notes that could still count toward a start.
        case idle(recent: [Date])
        case playing(lastNote: Date)
    }

    private static let startThreshold = 3
    private static let startWindow: TimeInterval = 10
    private static let endTail: TimeInterval = 5

    private var state = State.idle(recent: [])

    public init() {}

    /// The changes `event` makes to the MIDI session, which the caller stores in order.
    public mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {
        case (.idle(let recent), .noteOn(let date)):
            // Notes dated after this one, as before the clock stepped back, can't start a session in the future.
            let window = recent.filter { (0..<Self.startWindow).contains(date.timeIntervalSince($0)) } + [date]
            guard window.count >= Self.startThreshold, let first = window.min() else {
                state = .idle(recent: window)
                return []
            }
            state = .playing(lastNote: date)
            return [.start(at: first)]
        case (.playing(let last), .noteOn(let date)):
            state = .playing(lastNote: max(last, date))
            return []
        case (.playing(let last), .stop(let date)):
            state = .idle(recent: [])
            return [.end(afterLastNote: last, at: min(date, last + Self.endTail))]
        case (.idle, .stop):
            return []
        }
    }

    /// Follows the stored session: playing a running or paused MIDI session from its last change, if that's
    /// later than the last note, and idle otherwise. An ended MIDI session, which history couldn't take, is
    /// idle too, as nothing can change it.
    public mutating func sync(with session: PracticeSession?) {
        guard let session, session.source == .midi, session.state != .ended else {
            if case .playing = state { state = .idle(recent: []) }
            return
        }
        if case .playing(let last) = state, last > session.latestEvent { return }
        state = .playing(lastNote: session.latestEvent)
    }
}
