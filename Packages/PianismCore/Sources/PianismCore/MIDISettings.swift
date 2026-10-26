import Foundation

/// The timeouts of a MIDI session (MIDI-1), which Debug builds shorten for the end-to-end tests. SET-1 (#50) makes
/// them the user's settings.
public struct MIDISettings: Sendable {
    /// The silence after which a MIDI session pauses, at its last note.
    public var pauseAfter: TimeInterval = 60
    /// The silence after which a MIDI session ends, 5 s after its last note, and is saved.
    public var saveAfter: TimeInterval = 600
    /// The played time under which an ended MIDI session isn't practice, so it's dropped.
    public var minimumPlayed: TimeInterval = 60

    public init() {}
}
