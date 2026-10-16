import Foundation
import PianismCore
import SwiftData
import Synchronization

/// Finished sessions, kept in SwiftData on this device (HIS-1; ADR 0004, as amended by ADR 0006).
///
/// Sync through iCloud is off until SYN-1 (#15) deploys the schema.
public final class SwiftDataSessionHistory: SessionHistory {
    /// The open store, or why it couldn't open, which every call then throws. That way the app keeps
    /// running: History says it couldn't load, and Practice keeps an ended session in its own file.
    let container: Result<ModelContainer, any Error>
    /// Saves run one at a time, so two saves of a new session can't both insert it (ADR 0006).
    private let saving = Mutex(())

    /// Opens the store at `url`, creating it and its folder if needed.
    public init(url: URL) {
        container = Result {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try ModelContainer(
                for: Schema(versionedSchema: HistorySchemaV1.self),
                migrationPlan: HistoryMigrationPlan.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
        }
    }

    public func sessions() throws -> [PracticeSession] {
        try ModelContext(container.get()).fetch(FetchDescriptor<SessionRecord>()).map { try $0.session() }
    }

    public func save(_ session: PracticeSession) throws {
        try saving.withLock { _ in
            let context = ModelContext(try container.get())
            let id = session.id
            let existing = try context.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id }))
            let record = existing.first ?? SessionRecord()
            if existing.isEmpty {
                context.insert(record)
            }
            try record.update(from: session)
            try context.save()
        }
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
        timeZoneID = session.timeZone?.identifier ?? ""
        let stored = session.pauses.map { StoredPauses.Pause(start: $0.start, end: $0.end ?? ended) }
        pauses = stored.isEmpty ? Data() : try JSONEncoder().encode(StoredPauses(pauses: stored))
    }

    /// The session this record holds, rebuilt through the steps that made it, so it obeys the same
    /// rules as any other session.
    fileprivate func session() throws -> PracticeSession {
        var session = PracticeSession(id: id, startedAt: startedAt, timeZone: TimeZone(identifier: timeZoneID))
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
