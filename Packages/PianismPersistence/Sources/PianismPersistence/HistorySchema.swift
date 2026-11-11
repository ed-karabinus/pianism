import Foundation
import SwiftData

/// How finished sessions and tags were stored until TAG-5: schema v1 of ADR 0004, as amended by ADR 0006.
///
/// It's declared whole, as the ADRs' tables define it, including fields whose features hadn't landed
/// then. It's been in CloudKit's Production environment since 2026-10-21, and stores on devices still
/// have it, so it never changes: migrations start from it (ADR 0008).
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
        /// A `PracticeSession.Source`; MIDI-1 adds `midi`.
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
        /// Encrypted in iCloud, as the user's own words, like a session's note.
        @Attribute(.allowsCloudEncryption) var name: String = ""
        var isArchived: Bool = false  // mutate:ignore - nothing makes a v1 tag now, and stores keep the value they have
        /// Encrypted in iCloud, like `name`.
        @Attribute(.allowsCloudEncryption) var composer: String = ""
        /// In beats per minute.
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

/// Schema v1 and the tag a tag sits inside (TAG-5, ADR 0013): the schema this version stores, and the second one
/// deployed to CloudKit. Sessions are stored as in v1, by the same class.
enum HistorySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [HistorySchemaV1.SessionRecord.self, TagRecord.self] }

    /// v1's tag record, with ``parentID``. CloudKit names a record type after the class, so it keeps v1's name:
    /// any other would deploy a second tag record type, forever (ADR 0013).
    @Model
    final class TagRecord {
        /// A lowercase UUID.
        var id: String = ""
        /// `piece` or `skill`; an unknown value reads as `piece`.
        var kind: String = "piece"
        /// Encrypted in iCloud, as the user's own words, like a session's note.
        @Attribute(.allowsCloudEncryption) var name: String = ""
        var isArchived: Bool = false
        /// Encrypted in iCloud, like `name`.
        @Attribute(.allowsCloudEncryption) var composer: String = ""
        /// In beats per minute.
        var targetTempo: Int?
        /// The ID of the tag this one was merged into; empty if none.
        var mergedInto: String = ""
        /// The ID of the tag this one sits inside; empty at the top level. Plain, like `mergedInto`: it's an ID, not
        /// the user's words, and a field's encryption can't change once deployed (ADR 0013).
        var parentID: String = ""
        var createdAt: Date = Date.distantPast
        var modifiedAt: Date = Date.distantPast
        var version: Int = 1
        /// Set by a later version that deletes tags, so this one hides them too (ADR 0006).
        var deletedAt: Date?

        init() {}
    }
}

typealias SessionRecord = HistorySchemaV1.SessionRecord
typealias TagRecord = HistorySchemaV2.TagRecord

/// Migrations between schema versions: lightweight stages only (ADR 0006).
enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self, HistorySchemaV2.self] }
    /// v2 only adds a field with a default, so Core Data would infer this stage, and no test can tell it's here. It's
    /// written out so the plan names every step between versions (ADR 0006, 0013).
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: HistorySchemaV1.self, toVersion: HistorySchemaV2.self)]
    }
}

/// The JSON in ``SessionRecord/pauses``, fixed by ADR 0006. Changing it changes stored data.
struct StoredPauses: Codable {
    struct Pause: Codable {
        var start: Date
        var end: Date
    }

    var pauses: [Pause]
}
