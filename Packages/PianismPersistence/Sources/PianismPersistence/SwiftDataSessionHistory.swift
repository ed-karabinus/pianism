import Foundation
import PianismCore
import SwiftData
import Synchronization
import os

/// Finished sessions, kept in the ``HistoryStore`` (HIS-1; ADR 0004, as amended by ADR 0006).
public final class SwiftDataSessionHistory: SessionHistory {
    let store: HistoryStore
    /// Saves run one at a time, so two saves of a new session can't both insert it (ADR 0006).
    private let saving = Mutex(())
    private let clock: any WallClock
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    /// A history kept in `store`. `clock` stamps when each record last changed.
    public init(store: HistoryStore, clock: any WallClock) {
        self.store = store
        self.clock = clock
    }

    /// Each ID once, as its latest change, leaving out an ID with any deleted record (ADR 0004,
    /// 0006). A record that can't be rebuilt is left out too, so it can't hide the rest.
    public func sessions() throws -> [PracticeSession] {
        let records = try ModelContext(store.container()).fetch(FetchDescriptor<SessionRecord>())
        return Dictionary(grouping: records, by: \.id).values.compactMap { duplicates in
            guard let latest = Self.shown(among: duplicates) else { return nil }
            do {
                return try latest.session()
            } catch {
                logger.error(  // mutate:ignore - a log line; no test reads logs
                    "Skipped session \(latest.id, privacy: .public): it can't be rebuilt: \(error)")
                return nil
            }
        }
    }

    public func save(_ session: PracticeSession) throws {
        try saving.withLock { _ in
            let context = ModelContext(try store.container())
            // A record with this ID, even a deleted one, is never replaced (ADR 0004, as amended).
            guard try context.fetchCount(Self.copies(of: session.id)) == 0 else { return }
            let record = SessionRecord()
            context.insert(record)
            try write(session, to: record, modifiedAt: clock.now)
            try context.save()
        }
    }

    public func canEdit(id: UUID) throws -> Bool {
        let copies = try ModelContext(store.container()).fetch(Self.copies(of: id))
        return Self.shown(among: copies).map { $0.version <= HistoryStore.recordVersion } ?? false
    }

    public func edit(_ session: PracticeSession) throws {
        try saving.withLock { _ in
            let context = ModelContext(try store.container())
            guard let shown = Self.shown(among: try context.fetch(Self.copies(of: session.id))) else { return }
            guard shown.version <= HistoryStore.recordVersion else { throw RecordFromNewerVersion() }
            // Never earlier than before: a copy from a device whose clock runs ahead must not overtake it.
            try write(session, to: shown, modifiedAt: max(clock.now, shown.modifiedAt))
            try context.save()
        }
    }

    /// Writes `session` into `record`, stamped with this app's record version (ADR 0006).
    private func write(_ session: PracticeSession, to record: SessionRecord, modifiedAt: Date) throws {
        try record.update(from: session)
        record.modifiedAt = modifiedAt
        record.version = HistoryStore.recordVersion  // mutate:ignore - the default until a release raises it
        // A record that wouldn't read back the same would hide the whole history, so refuse it:
        // the session then waits in the outbox (ADR 0007), where this log line explains it.
        // A record that can't be rebuilt at all is refused too, not treated as history failing.
        guard (try? record.session()) == session else {
            logger.error(  // mutate:ignore - a log line; no test reads logs
                "Refused session \(session.id, privacy: .public): it wouldn't read back the same")
            throw SessionRefused()
        }
    }

    private static func copies(of id: UUID) -> FetchDescriptor<SessionRecord> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    /// The copy of a session that shows: its latest change, or none if any copy was deleted (ADR 0006).
    private static func shown(among copies: [SessionRecord]) -> SessionRecord? {
        guard copies.allSatisfy({ $0.deletedAt == nil }) else { return nil }
        return copies.max { $0.modifiedAt < $1.modifiedAt }  // mutate:ignore - only ties differ
    }
}

extension SessionRecord {
    /// Writes an ended `session` into this record.
    fileprivate func update(from session: PracticeSession) throws {
        guard let ended = session.endedAt else {
            preconditionFailure("Only ended sessions move to history (ADR 0003)")
        }
        id = session.id
        startedAt = session.startedAt
        endedAt = ended
        // A zone this OS doesn't know reads as none; an edit must keep it (ADR 0006).
        timeZoneID = session.timeZone?.identifier ?? timeZoneID
        tagIDs = session.tagIDs
        let stored = session.pauses.map { StoredPauses.Pause(start: $0.start, end: $0.end ?? ended) }
        pauses = stored.isEmpty ? Data() : try JSONEncoder().encode(StoredPauses(pauses: stored))
    }

    /// The session this record holds, rebuilt through the steps that made it, so it obeys the same
    /// rules as any other session.
    fileprivate func session() throws -> PracticeSession {
        var session = PracticeSession(id: id, startedAt: startedAt, timeZone: TimeZone(identifier: timeZoneID))
        try session.setTags(tagIDs)
        if !pauses.isEmpty {
            for pause in try JSONDecoder().decode(StoredPauses.self, from: pauses).pauses {
                try session.pause(at: pause.start)
                try session.resume(at: pause.end)
            }
        }
        try session.stop(at: endedAt)
        return session
    }
}
