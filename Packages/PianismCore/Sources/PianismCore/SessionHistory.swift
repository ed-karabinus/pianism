import Foundation

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

    /// Whether the saved session with `id` can be edited: `false` if a newer version wrote it, which
    /// this one could damage, or it was deleted (ADR 0006).
    func canEdit(id: UUID) throws -> Bool

    /// Replaces the saved session with `session`'s ID by `session`, as edited (SES-5). Changes nothing
    /// if it was never saved or was deleted. Throws ``RecordFromNewerVersion`` if a newer version wrote it.
    func edit(_ session: PracticeSession) throws

    /// Deletes the saved session with `id` for good, so it no longer reads and saving it again changes nothing
    /// (SES-5, ADR 0006). Changes nothing if it was never saved or was already deleted. Throws
    /// ``RecordFromNewerVersion`` if a newer version wrote it.
    func delete(id: UUID) throws
}
