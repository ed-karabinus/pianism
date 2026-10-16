import Foundation
import PianismCore
import SwiftData
import Synchronization
import os

/// Finished sessions, kept in SwiftData on this device (HIS-1; ADR 0004, as amended by ADR 0006).
///
/// Sync through iCloud is off until SYN-1 (#15) deploys the schema.
public final class SwiftDataSessionHistory: SessionHistory {
    private let url: URL
    /// The store once it has opened. Until then, each call tries to open it and throws why it
    /// couldn't, so a passing failure such as a full disk heals itself, and the app keeps running:
    /// History says it couldn't load, and finished sessions wait in the outbox (ADR 0007).
    private let opened = Mutex<ModelContainer?>(nil)
    /// Saves run one at a time, so two saves of a new session can't both insert it (ADR 0006).
    private let saving = Mutex(())
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    /// A history stored at `url`, which is created, with its folder, on first use.
    public init(url: URL) {
        self.url = url
    }

    public func sessions() throws -> [PracticeSession] {
        try ModelContext(container()).fetch(FetchDescriptor<SessionRecord>()).map { try $0.session() }
    }

    func container() throws -> ModelContainer {
        try opened.withLock { opened in
            if let opened { return opened }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let container = try ModelContainer(
                for: Schema(versionedSchema: HistorySchemaV1.self),
                migrationPlan: HistoryMigrationPlan.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            opened = container
            return container
        }
    }

    public func save(_ session: PracticeSession) throws {
        try saving.withLock { _ in
            let context = ModelContext(try container())
            let id = session.id
            let existing = try context.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id }))
            let record = existing.first ?? SessionRecord()
            if existing.isEmpty {
                context.insert(record)
            }
            try record.update(from: session)
            // A record that wouldn't read back the same would hide the whole history, so refuse it:
            // the session then waits in the outbox (ADR 0007), where this log line explains it.
            guard try record.session() == session else {
                logger.error("Refused session \(session.id, privacy: .public): it wouldn't read back the same")
                throw HistoryError.wouldNotReadBack
            }
            try context.save()
        }
    }
}

/// Why ``SwiftDataSessionHistory`` refused to save a session.
enum HistoryError: Error {
    /// Stored, the session would read back as something else.
    case wouldNotReadBack
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
