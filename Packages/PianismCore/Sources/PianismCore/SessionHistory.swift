/// Thrown by ``SessionHistory/save(_:)`` when history works but can't store this one session.
/// Moving waiting sessions skips past it rather than stopping (ADR 0007).
public struct SessionRefused: Error {
    public init() {}
}

/// Where finished sessions are kept (HIS-1, ADR 0004).
public protocol SessionHistory: Sendable {
    /// Every saved session, in no particular order.
    func sessions() throws -> [PracticeSession]

    /// Saves `session`, replacing any saved session with the same ID, so saving twice is harmless.
    func save(_ session: PracticeSession) throws
}
