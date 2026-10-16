import Foundation
import SwiftData

/// How finished sessions are stored: schema v1 of ADR 0004, as amended by ADR 0006.
///
/// Once it reaches CloudKit, this schema can only grow. It's declared whole, including the fields
/// whose features haven't landed yet, because changing a model means keeping a copy of its old
/// version forever.
enum HistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SessionRecord.self] }

    @Model
    final class SessionRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date.distantPast
        var endedAt: Date = Date.distantPast
        /// The pauses as JSON (``StoredPauses``); empty means none.
        var pauses: Data = Data()
        // periphery:ignore - schema v1; tags arrive with TAG-2
        var tagIDs: [String] = []
        // periphery:ignore - schema v1; notes arrive with SES-5
        var note: String = ""
        // periphery:ignore - schema v1; manual entries (SES-5) and MIDI (MIDI-1) set it
        var source: String = "timer"
        /// Such as `America/Los_Angeles`; empty if unknown.
        var timeZoneID: String = ""
        // periphery:ignore - schema v1; settles duplicates once sync is on (SYN-1)
        var modifiedAt: Date = Date.distantPast
        // periphery:ignore - schema v1; checked once sessions can be edited (SES-5, ADR 0006)
        var version: Int = 1
        // periphery:ignore - schema v1; deleting arrives with SES-5
        var deletedAt: Date?

        init() {}
    }
}

typealias SessionRecord = HistorySchemaV1.SessionRecord

/// Migrations between schema versions: lightweight stages only (ADR 0006).
enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// The JSON in ``SessionRecord/pauses``, fixed by ADR 0006. Changing it changes stored data.
struct StoredPauses: Codable, Equatable {
    struct Pause: Codable, Equatable {
        var start: Date
        var end: Date
    }

    var pauses: [Pause]
}
