/// The keys under which settings are kept on this device, in the app's own defaults (SET-1, decided with Ed,
/// 2026-11-02). A key's name is permanent: renaming one loses what was set under it.
enum SettingsKey {
    /// Kept since SES-5 by the editor's "Don't show again".
    static let showsOverlapWarning = "showsOverlapWarning"
    /// The nudge, in seconds (SES-3).
    static let stillPracticingAfter = "stillPracticingAfter"
    /// The cap, in seconds (SES-4).
    static let automaticCapAfter = "automaticCapAfter"
    /// Whether a session past the nudge may notify, if the system allows it (SES-3).
    static let notifiesStillPracticing = "notifiesStillPracticing"
    /// How many notes start a MIDI session (MIDI-1).
    static let midiStartNotes = "midiStartNotes"
    /// The silence that pauses a MIDI session, in seconds (MIDI-1).
    static let midiPauseAfter = "midiPauseAfter"
    /// The silence that ends and saves a MIDI session, in seconds (MIDI-1).
    static let midiSaveAfter = "midiSaveAfter"
}
