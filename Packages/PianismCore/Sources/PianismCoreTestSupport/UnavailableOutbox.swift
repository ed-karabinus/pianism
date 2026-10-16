import Foundation
import PianismCore

/// An outbox that can't be read or written, as on a full disk.
public struct UnavailableOutbox: SessionOutbox {
    public struct Failure: Error {}

    public init() {}

    public func sessions() throws -> [PracticeSession] {
        throw Failure()
    }

    public func add(_: PracticeSession) throws {
        throw Failure()
    }

    public func remove(id _: UUID) throws {
        throw Failure()
    }
}
