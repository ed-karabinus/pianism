/// The keys under which settings are kept on this device, in the app's own defaults (SET-1, decided with Ed,
/// 2026-11-02). A key's name is permanent: renaming one loses what was set under it.
enum SettingsKey {
    /// Kept since SES-5 by the editor's "Don't show again".
    static let showsOverlapWarning = "showsOverlapWarning"
    /// The nudge, in seconds (SES-3).
    static let stillPracticingAfter = "stillPracticingAfter"
    /// The cap, in seconds (SES-4).
    static let automaticCapAfter = "automaticCapAfter"
}
