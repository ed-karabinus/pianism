/// Where finished sessions are kept (HIS-1, ADR 0004).
public protocol SessionHistory: Sendable {
    /// Saves `session`, replacing any saved session with the same ID, so saving twice is harmless.
    // periphery:ignore:parameters session - every real history stores it; only stand-ins ignore it
    func save(_ session: PracticeSession) throws
}
