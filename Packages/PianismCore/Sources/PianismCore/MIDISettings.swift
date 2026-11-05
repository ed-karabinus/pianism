import Foundation

/// How a MIDI session starts, pauses and ends (MIDI-1), as set in Settings (SET-1). Debug builds shorten the
/// timeouts for the end-to-end tests.
public struct MIDISettings: Sendable {
    /// How many notes within 10 s start a MIDI session. Under one is read as one: a stored or
    /// launch-overridden value under its smallest is meaningless, and settings read as their smallest.
    public var startNotes = 3 { didSet { startNotes = max(startNotes, 1) } }
    /// The silence after which a MIDI session pauses, at its last note.
    public var pauseAfter: TimeInterval = 60 { didSet { pauseAfter = max(pauseAfter, 0) } }
    /// The silence after which a MIDI session ends, 5 s after its last note, and is saved.
    public var saveAfter: TimeInterval = 600 { didSet { saveAfter = max(saveAfter, 0) } }
    /// The played time under which an ended MIDI session isn't practice, so it's dropped.
    public var minimumPlayed: TimeInterval = 60 { didSet { minimumPlayed = max(minimumPlayed, 0) } }

    public init() {}
}
