/// Shows practice outside the app: today's total and the running session on the widget (GLN-2, ADR 0010).
public protocol PracticeGlance: Sendable {
    /// Shows the day's finished practice.
    func show(_ totals: PracticeTotals)
    /// Shows the stored session, or none; an ended one still stored counts as none.
    func show(_ session: PracticeSession?)
}
