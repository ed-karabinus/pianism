import Foundation
import PianismCore
import Synchronization

/// A history that can't be reached until it heals, as when its store fails to open and later opens.
public final class FlakyHistory: SessionHistory {
    public struct Failure: Error {
        public init() {}
    }

    /// What the history holds, readable by tests even while it fails.
    public let saved = InMemorySessionHistory()
    private let isFailing = Mutex(true)

    public init() {}

    public func heal() {
        isFailing.withLock { $0 = false }
    }

    public func sessions() throws -> [PracticeSession] {
        try failIfUnreachable()
        return saved.sessions()
    }

    public func save(_ session: PracticeSession) throws {
        try failIfUnreachable()
        saved.save(session)
    }

    public func canEdit(id: UUID) throws -> Bool {
        try failIfUnreachable()
        return saved.canEdit(id: id)
    }

    public func edit(_ session: PracticeSession) throws {
        try failIfUnreachable()
        try saved.edit(session)
    }

    public func delete(id: UUID) throws {
        try failIfUnreachable()
        try saved.delete(id: id)
    }

    private func failIfUnreachable() throws {
        if isFailing.withLock({ $0 }) { throw Failure() }
    }
}
