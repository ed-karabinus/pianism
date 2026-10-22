import CoreData
import Foundation
import PianismCore
import PianismCoreTestSupport
import SwiftData
import Testing

@testable import PianismPersistence

/// History stores as builds have written them to devices, opened with the current schema. Every build
/// must open every fixture, or an update loses the user's history (ADR 0004). The fixtures were replaced
/// once, on 2026-10-20, when tag IDs became JSON while only the owner's iPhone had history (ADR 0006). Never edit one;
/// when the schema changes, add one that sets every field to a value other than its default, so a
/// change in how a field is stored fails a test (ADR 0006). Write it through `HistoryStore` from a
/// scratch test, then run `sqlite3 <store> 'PRAGMA journal_mode=DELETE'`: until then, its records
/// may be only in the `-wal` file beside it.
final class HistoryStoreFormatTests {
    let clock = ManualClock()
    let directory = FileManager.default.temporaryDirectory.appending(path: "HistoryStoreFormatTests-\(UUID())")
    /// 2027-01-01 00:00:00.25 UTC, when the fixtures' sessions start.
    let start = Date(timeIntervalSinceReferenceDate: 820_454_400.25)
    let vienna = TimeZone(identifier: "Europe/Vienna")

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("ADR 0006: a store with every field of schema v1 set reads back exactly, stored and through the adapters")
    func v1StoreReads() throws {
        let store = try open("history-v1")
        let context = ModelContext(try store.container())
        let live = try #require(UUID(uuidString: "9C4E2B7A-5D1F-4A3C-8B6E-0F2D4A6C8E13"))
        let deleted = try #require(UUID(uuidString: "2D7F1C3B-5A90-4C3B-9A8E-6B1E2A4C0F5D"))
        let ballade = "5e0c7a4d-2b1f-4c8e-9a3d-7f6b1e2c4d80"
        let pedalling = "b3f1d2e4-6a5c-4b7d-8e9f-0a1b2c3d4e5f"
        let gMinor = "c7d8e9f0-1a2b-4c3d-8e4f-5a6b7c8d9e0f"
        let pauses =
            #"{"pauses":[{"start":820454700.5,"end":820454760.75},{"start":820455300.375,"end":820455361.125}]}"#
        let tagIDs = [ballade, BuiltInSkill.scales.rawValue, pedalling]
        let storedTagIDs = Data(#"["\#(ballade)","skill.scales","\#(pedalling)"]"#.utf8)

        // Every field in schema order. Two records have version 2, as sync from a newer app leaves them.
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(
            sessions.map(\.fields) == [
                [
                    deleted, start - 86_400, start - 85_199.5, Data(), Data(), "", "timer", "America/Los_Angeles",
                    start - 3_600, 2, start - 3_600,
                ],
                [
                    live, start, start + 1_800.625, Data(pauses.utf8), storedTagIDs, "Left hand alone, slowly", "midi",
                    "Europe/Vienna", start + 1_805.5, 1, nil,
                ],
            ])
        let tags = try context.fetch(FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(
            tags.map(\.fields) == [
                [ballade, "piece", "Ballade No. 1", false, "Chopin", 72, "", start - 172_800, start - 7_200, 1, nil],
                [pedalling, "skill", "Pedalling", true, "", nil, "", start - 172_740, start - 7_140, 1, nil],
                [gMinor, "piece", "Chopin G minor", true, "", nil, ballade, start - 172_680, start - 7_080, 2, nil],
            ])

        var session = PracticeSession(id: live, startedAt: start, timeZone: vienna)
        try session.setTags(tagIDs)
        try session.pause(at: start + 300.25)
        try session.resume(at: start + 360.5)
        try session.pause(at: start + 900.125)
        try session.resume(at: start + 960.875)
        try session.stop(at: start + 1_800.625)
        try session.editNote("Left hand alone, slowly")
        #expect(try SwiftDataSessionHistory(store: store, clock: clock).sessions() == [session])
        #expect(
            Set(try SwiftDataTagLibrary(store: store, clock: clock).tags()) == [
                Tag(
                    id: ballade, kind: .piece, name: "Ballade No. 1", isArchived: false, createdAt: start - 172_800,
                    composer: "Chopin", targetTempo: 72),
                Tag(id: pedalling, kind: .skill, name: "Pedalling", isArchived: true, createdAt: start - 172_740),
                Tag(
                    id: gMinor, kind: .piece, name: "Chopin G minor", isArchived: true, mergedInto: ballade,
                    createdAt: start - 172_680, isReadOnly: true),
            ])
    }

    @Test("SYN-1, ADR 0006: a store with a deleted tag, the field added before sync, reads it and leaves it out")
    func deletedTagStoreReads() throws {
        let store = try open("history-v1-deleted-tag")
        let pedalling = "b3f1d2e4-6a5c-4b7d-8e9f-0a1b2c3d4e5f"

        let tags = try ModelContext(try store.container()).fetch(FetchDescriptor<TagRecord>())
        #expect(
            tags.first { $0.id == pedalling }?.fields
                == [
                    pedalling, "skill", "Pedalling", true, "", nil, "", start - 172_740, start - 7_140, 1,
                    start - 7_000,
                ])
        #expect(
            Set(try SwiftDataTagLibrary(store: store, clock: clock).tags().map(\.name)) == [
                "Ballade No. 1", "Chopin G minor",
            ])
        #expect(try SwiftDataSessionHistory(store: store, clock: clock).sessions().count == 1)
    }

    @Test("SYN-1: schema v1 is exactly what the CloudKit deploy freezes, and the expected export lists every field")
    func schemaIsWhatTheDeployFreezes() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: HistorySchemaV1.models))
        let properties = model.entities.flatMap { entity in entity.properties.map { (entity.name ?? "", $0) } }

        // Changing any line changes what syncs; after the deploy, only adding fields is possible (ADR 0008).
        #expect(
            properties.map { "\($0).\($1.name) \(Self.describe($1))" }.sorted() == [
                "SessionRecord.deletedAt date optional",
                "SessionRecord.endedAt date default",
                "SessionRecord.id UUID default",
                "SessionRecord.modifiedAt date default",
                "SessionRecord.note string default encrypted",
                "SessionRecord.pauses binary default",
                "SessionRecord.source string default",
                "SessionRecord.startedAt date default",
                "SessionRecord.tagIDs binary default",
                "SessionRecord.timeZoneID string default",
                "SessionRecord.version integer64 default",
                "TagRecord.composer string default encrypted",
                "TagRecord.createdAt date default",
                "TagRecord.deletedAt date optional",
                "TagRecord.id string default",
                "TagRecord.isArchived boolean default",
                "TagRecord.kind string default",
                "TagRecord.mergedInto string default",
                "TagRecord.modifiedAt date default",
                "TagRecord.name string default encrypted",
                "TagRecord.targetTempo integer64 optional",
                "TagRecord.version integer64 default",
            ])
        #expect(model.entities.allSatisfy { $0.uniquenessConstraints.isEmpty })
        // The fields the deploy must contain: one missing there makes every record that sets it fail to sync.
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let expected = try String(
            contentsOf: repository.appending(path: "docs/cloudkit/schema-v1-fields.txt"), encoding: .utf8)
        // Encryption too, as a field's can't change after the deploy.
        for (entity, property) in properties {
            let field = "CD_\(entity).CD_\(property.name) "
            let encrypted = (property as? NSAttributeDescription)?.allowsCloudEncryption == true
            #expect(expected.contains(field), "\(entity).\(property.name)")
            #expect(expected.contains(field + "ENCRYPTED ") == encrypted, "\(entity).\(property.name) encryption")
        }
    }

    /// The type and options CloudKit sees for `property`.
    private static func describe(_ property: NSPropertyDescription) -> String {
        guard let attribute = property as? NSAttributeDescription else { return "relationship" }
        let types: [NSAttributeType: String] = [
            .stringAttributeType: "string", .dateAttributeType: "date", .UUIDAttributeType: "UUID",
            .binaryDataAttributeType: "binary", .transformableAttributeType: "transformable",
            .integer64AttributeType: "integer64", .booleanAttributeType: "boolean",
        ]
        var words = [types[attribute.attributeType] ?? "type \(attribute.attributeType.rawValue)"]
        words.append(attribute.defaultValue != nil ? "default" : attribute.isOptional ? "optional" : "required")
        words += [attribute.valueTransformerName, attribute.allowsCloudEncryption ? "encrypted" : nil].compactMap(
            \.self)
        return words.joined(separator: " ")
    }

    @Test("SES-5, ADR 0006: deleting a v1 session clears only its note and tags, and marks when it was deleted")
    func v1SessionDeletes() throws {
        let store = try open("history-v1")
        let live = try #require(UUID(uuidString: "9C4E2B7A-5D1F-4A3C-8B6E-0F2D4A6C8E13"))
        let context = ModelContext(try store.container())
        let before = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first { $0.id == live }).fields
        let history = SwiftDataSessionHistory(store: store, clock: clock)

        try history.delete(id: live)

        let after = try #require(
            try ModelContext(store.container()).fetch(FetchDescriptor<SessionRecord>()).first { $0.id == live })
        var expected = before
        expected[4] = Data()
        expected[5] = ""
        // The fixture's change is later than this clock, so it stays the latest.
        expected[10] = clock.now
        #expect(after.fields == expected)
        #expect(try history.sessions().isEmpty)
    }

    /// A copy of the fixture `name`, so opening it can't change the original.
    private func open(_ name: String) throws -> HistoryStore {
        let fixture = try #require(
            Bundle.module.url(forResource: name, withExtension: "store", subdirectory: "Fixtures"))
        let url = directory.appending(path: "\(name)/History.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: url)
        return HistoryStore(url: url)
    }
}

// `as` pins the numeric types, which AnyHashable compares across Int and Double.
extension SessionRecord {
    fileprivate var fields: [AnyHashable?] {
        [id, startedAt, endedAt, pauses, tagIDs, note, source, timeZoneID, modifiedAt, version as Int, deletedAt]
    }
}

extension TagRecord {
    fileprivate var fields: [AnyHashable?] {
        [
            id, kind, name, isArchived, composer, targetTempo as Int?, mergedInto, createdAt, modifiedAt,
            version as Int,
            deletedAt,
        ]
    }
}
