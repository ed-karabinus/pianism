import Foundation

/// How a MIDI session starts, pauses and ends (MIDI-1), as set in Settings (SET-1). Debug builds shorten the
/// timeouts for the end-to-end tests.
public struct MIDISettings: Sendable {
    /// How many notes within 10 s start a MIDI session.
    public var startNotes = 3
    /// The silence after which a MIDI session pauses, at its last note.
    public var pauseAfter: TimeInterval = 60
    /// The silence after which a MIDI session ends, 5 s after its last note, and is saved.
    public var saveAfter: TimeInterval = 600
    /// The played time under which an ended MIDI session isn't practice, so it's dropped.
    public var minimumPlayed: TimeInterval = 60

    public init() {}
}
