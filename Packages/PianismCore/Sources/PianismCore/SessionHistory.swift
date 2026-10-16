/// Thrown by ``SessionHistory/save(_:)`` when history works but can't store this one session.
/// Moving waiting sessions skips past it rather than stopping (ADR 0007).
public struct SessionRefused: Error {
    public init() {}
}

/// Where finished sessions are kept (HIS-1, ADR 0004).
public protocol SessionHistory: Sendable {
    /// Every saved session, in no particular order.
    func sessions() throws -> [PracticeSession]

    /// Saves `session` unless a session with its ID is already saved, or was deleted. Saving twice is
    /// harmless, and a stale copy can't replace a later edit.
    func save(_ session: PracticeSession) throws
}
