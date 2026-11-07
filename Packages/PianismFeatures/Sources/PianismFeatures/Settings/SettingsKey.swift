/// The keys under which settings are kept on this device, in the app's own defaults (SET-1, decided with Ed,
/// 2026-11-02). A key's name is permanent: renaming one loses what was set under it.
enum SettingsKey {
    /// Kept since SES-5 by the editor's "Don't show again".
    static let showsOverlapWarning = "showsOverlapWarning"
    /// The days a week ``WeeklyGoal`` asks for (HIS-3).
    static let weeklyGoalDays = "weeklyGoalDays"
    /// A day's least practice to count toward it, in seconds (HIS-3).
    static let dailyMinimum = "dailyMinimum"
    /// Whether the first launch has been past the welcome, shown or not (ONB-1).
    static let hasDecidedWelcome = "hasDecidedWelcome"
    /// The nudge, in seconds (SES-3).
    static let stillPracticingAfter = "stillPracticingAfter"
    /// The cap, in seconds (SES-4).
    static let automaticCapAfter = "automaticCapAfter"
    /// Whether a session past the nudge may notify, if the system allows it (SES-3).
    static let notifiesStillPracticing = "notifiesStillPracticing"
    /// Whether the daily reminder is wanted, if the system allows it (SET-1).
    static let remindsDaily = "remindsDaily"
    /// The daily reminder's time, in minutes after local midnight (SET-1).
    static let dailyReminderMinute = "dailyReminderMinute"
    /// Whether anonymous analytics is on (ADR 0011).
    static let sharesUsage = "sharesUsage"
    /// How far this install is toward activation, as JSON (ADR 0011).
    static let activationProgress = "activationProgress"
    /// How many notes start a MIDI session (MIDI-1).
    static let midiStartNotes = "midiStartNotes"
    /// The silence that pauses a MIDI session, in seconds (MIDI-1).
    static let midiPauseAfter = "midiPauseAfter"
    /// The silence that ends and saves a MIDI session, in seconds (MIDI-1).
    static let midiSaveAfter = "midiSaveAfter"
}
