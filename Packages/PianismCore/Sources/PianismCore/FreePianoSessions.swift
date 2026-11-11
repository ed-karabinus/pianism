import Foundation

/// The piano sessions free before Pro: a piano starts the first 5 sessions it saves by itself, then only with Pro.
/// Starting by tapping is always free (PRO-2, ADR 0012).
public enum FreePianoSessions {
    /// How many piano sessions are free.
    public static let sessions = 5

    /// How many free piano sessions are left after `used`, never fewer than none.
    public static func left(afterUsing used: Int) -> Int {
        max(0, sessions - used)
    }

    /// The piano sessions used so far, each once: those `history` keeps, deleted ones included, so deleting gives
    /// none back, and those waiting in `outbox`.
    public static func used(history: any SessionHistory, outbox: any SessionOutbox) throws -> Int {
        let waiting = try outbox.sessions().filter { $0.source == .midi }.map(\.id)
        return try history.autoLoggedIDs().union(waiting).count
    }
}
