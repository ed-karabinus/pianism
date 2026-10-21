import Foundation
import SwiftData

/// How finished sessions and tags are stored: schema v1 of ADR 0004, as amended by ADR 0006.
///
/// It's declared whole, as the ADRs' tables define it, including fields whose features haven't
/// landed yet. It must be complete before SYN-1 promotes it to CloudKit, where nothing can be renamed
/// or removed; until then, it can still change in place.
enum HistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SessionRecord.self, TagRecord.self] }

    @Model
    final class SessionRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date.distantPast
        var endedAt: Date = Date.distantPast
        /// The pauses as JSON (``StoredPauses``); empty means none.
        var pauses: Data = Data()
        /// The tag IDs as a JSON array of strings; empty means none (ADR 0006).
        var tagIDs: Data = Data()
        /// Encrypted in iCloud, as the user's own words; a field's encryption can't change after SYN-1 deploys it.
        @Attribute(.allowsCloudEncryption) var note: String = ""
        // periphery:ignore - schema v1; manual entries (SES-5) and MIDI (MIDI-1) set it
        var source: String = "timer"
        /// Such as `America/Los_Angeles`; empty if unknown.
        var timeZoneID: String = ""
        var modifiedAt: Date = Date.distantPast
        var version: Int = 1
        var deletedAt: Date?

        init() {}
    }

    /// A tag the user added; built-in skills aren't stored (ADR 0004).
    @Model
    final class TagRecord {
        /// A lowercase UUID.
        var id: String = ""
        /// `piece` or `skill`; an unknown value reads as `piece`.
        var kind: String = "piece"
        var name: String = ""
        var isArchived: Bool = false
        // periphery:ignore - schema v1; piece details arrive with TAG-3
        var composer: String = ""
        // periphery:ignore - schema v1; piece details arrive with TAG-3, in BPM
        var targetTempo: Int?
        /// The ID of the tag this one was merged into; empty if none.
        var mergedInto: String = ""
        var createdAt: Date = Date.distantPast
        var modifiedAt: Date = Date.distantPast
        var version: Int = 1
        /// Set by a later version that deletes tags, so this one hides them too (ADR 0006).
        var deletedAt: Date?

        init() {}
    }
}

typealias SessionRecord = HistorySchemaV1.SessionRecord
typealias TagRecord = HistorySchemaV1.TagRecord

/// Migrations between schema versions: lightweight stages only (ADR 0006).
enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// The JSON in ``SessionRecord/pauses``, fixed by ADR 0006. Changing it changes stored data.
struct StoredPauses: Codable {
    struct Pause: Codable {
        var start: Date
        var end: Date
    }

    var pauses: [Pause]
}
