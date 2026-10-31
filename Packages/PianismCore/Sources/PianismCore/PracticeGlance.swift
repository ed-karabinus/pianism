/// Shows practice outside the app: today's total on the widget (GLN-2, ADR 0010).
public protocol PracticeGlance: Sendable {
    /// Shows the day's finished practice.
    func show(_ totals: PracticeTotals)
}
