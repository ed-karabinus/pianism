import Foundation

/// Where finished sessions wait while history can't save them, so practice never has to stop
/// (ADR 0007). History saves by ID, so moving a session from here twice is harmless.
public protocol SessionOutbox: Sendable {
    /// Every waiting session, in no particular order.
    func sessions() throws -> [PracticeSession]

    /// Adds `session`, replacing any waiting session with the same ID.
    func add(_ session: PracticeSession) throws

    /// Removes the waiting session with this ID.
    func remove(id: UUID) throws
}
