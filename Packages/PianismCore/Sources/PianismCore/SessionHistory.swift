/// Where finished sessions are kept (HIS-1, ADR 0004).
public protocol SessionHistory: Sendable {
    /// Saves `session`, replacing any saved session with the same ID, so saving twice is harmless.
    func save(_ session: PracticeSession) throws
}
