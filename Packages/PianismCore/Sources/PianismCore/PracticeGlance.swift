import Foundation

/// Shows practice outside the app: today's total and the running session on the widget, and the session as a Live
/// Activity (GLN-1, GLN-2, ADR 0010).
public protocol PracticeGlance: Sendable {
    /// Shows the day's finished practice.
    func show(_ totals: PracticeTotals)
    /// Shows the stored session, or none; an ended one still stored counts as none. `cap` is the practice time at
    /// which the session ends itself, so a clock outside the app stops there (SES-4), or `nil` when it isn't capped.
    func show(_ session: PracticeSession?, cappedAt cap: TimeInterval?)
}
