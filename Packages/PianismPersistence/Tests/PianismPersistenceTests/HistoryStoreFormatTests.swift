import Foundation
import PianismCore
import PianismCoreTestSupport
import SwiftData
import Testing

@testable import PianismPersistence

/// History stores as builds have written them to devices, opened with the current schema. Every build
/// must open every fixture, or an update loses the user's history (ADR 0004). Never edit a fixture;
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

    @Test("TAG-1: a store written before tags existed, as on the owner's iPhone, still opens with its session")
    func storeFromBeforeTagsOpens() throws {
        let store = try open("history-before-tags")
        let id = try #require(UUID(uuidString: "3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90"))
        var expected = PracticeSession(id: id, startedAt: start, timeZone: vienna)
        try expected.pause(at: start + 300.25)
        try expected.resume(at: start + 360.5)
        try expected.stop(at: start + 1_800.625)

        #expect(try SwiftDataSessionHistory(store: store, clock: clock).sessions() == [expected])
        #expect(try SwiftDataTagLibrary(store: store, clock: clock).tags().isEmpty)
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

        // Every field in schema order. Two records have version 2, as sync from a newer app leaves them.
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(
            sessions.map(\.fields) == [
                [
                    deleted, start - 86_400, start - 85_199.5, Data(), [String](), "", "timer", "America/Los_Angeles",
                    start - 3_600, 2, start - 3_600,
                ],
                [
                    live, start, start + 1_800.625, Data(pauses.utf8), tagIDs, "Left hand alone, slowly", "midi",
                    "Europe/Vienna", start + 1_805.5, 1, nil,
                ],
            ])
        let tags = try context.fetch(FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(
            tags.map(\.fields) == [
                [ballade, "piece", "Ballade No. 1", false, "Chopin", 72, "", start - 172_800, start - 7_200, 1],
                [pedalling, "skill", "Pedalling", true, "", nil, "", start - 172_740, start - 7_140, 1],
                [gMinor, "piece", "Chopin G minor", true, "", nil, ballade, start - 172_680, start - 7_080, 2],
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
                Tag(id: ballade, kind: .piece, name: "Ballade No. 1", isArchived: false, createdAt: start - 172_800),
                Tag(id: pedalling, kind: .skill, name: "Pedalling", isArchived: true, createdAt: start - 172_740),
                Tag(
                    id: gMinor, kind: .piece, name: "Chopin G minor", isArchived: true, mergedInto: ballade,
                    createdAt: start - 172_680, isReadOnly: true),
            ])
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
        expected[4] = [String]()
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
        [id, kind, name, isArchived, composer, targetTempo as Int?, mergedInto, createdAt, modifiedAt, version as Int]
    }
}
