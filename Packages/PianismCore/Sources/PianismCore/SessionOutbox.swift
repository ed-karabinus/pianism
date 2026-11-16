import Foundation

/// Where finished sessions wait while history can't save them, so practice never has to stop
/// (ADR 0007). History saves by ID, so moving a session from here twice is harmless.
public protocol SessionOutbox: Sendable {
    /// Every waiting session, in no particular order.
    func sessions() throws -> [PracticeSession]

    /// Adds `session`, replacing any waiting session with the same ID.
    func add(_ session: PracticeSession) throws

    /// Removes the waiting session with this ID, if there is one.
    func remove(id: UUID) throws

    /// How many waiting sessions this version can't read, as a newer one wrote them or the format broke, which
    /// ``sessions()`` leaves out until a version that can read them comes (#87). None if it can't tell.
    func unreadableCount() -> Int
}
