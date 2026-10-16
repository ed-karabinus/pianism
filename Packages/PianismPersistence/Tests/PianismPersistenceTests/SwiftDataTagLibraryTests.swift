import Foundation
import PianismCore
import PianismCoreTestSupport
import SwiftData
import Testing

@testable import PianismPersistence

/// Integration tests against a real SwiftData store in a fresh temporary directory.
final class SwiftDataTagLibraryTests {
    let clock = ManualClock()
    let directory = FileManager.default.temporaryDirectory.appending(path: "SwiftDataTagLibraryTests-\(UUID())")
    var storeURL: URL { directory.appending(path: "History/History.store") }
    var library: SwiftDataTagLibrary { SwiftDataTagLibrary(store: HistoryStore(url: storeURL), clock: clock) }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("TAG-1: added, renamed and archived tags are still there when the store is opened again")
    func tagsSurviveReopening() throws {
        let library = self.library
        let added = clock.now
        let ballade = try library.add(name: "Ballade No. 1", kind: .piece)
        let pedalling = try library.add(name: "Pedalling", kind: .skill)
        #expect(try records().allSatisfy { $0.createdAt == added && $0.modifiedAt == added })
        clock.advance(by: 60)
        try library.rename(id: ballade.id, to: "Ballade No. 1 in G minor")
        try library.setArchived(true, id: pedalling.id)

        let reopened = self.library

        #expect(
            Set(try reopened.tags()) == [
                Tag(id: ballade.id, kind: .piece, name: "Ballade No. 1 in G minor"),
                Tag(id: pedalling.id, kind: .skill, name: "Pedalling", isArchived: true),
            ])
        #expect(UUID(uuidString: ballade.id) != nil && ballade.id == ballade.id.lowercased())
        let records = try records()
        #expect(records.allSatisfy { $0.createdAt == added && $0.modifiedAt == clock.now })
    }

    @Test("TAG-1: an archived tag can be brought back")
    func unarchives() throws {
        let tag = try library.add(name: "Arpeggios in thirds", kind: .skill)
        try library.setArchived(true, id: tag.id)

        try library.setArchived(false, id: tag.id)

        #expect(try library.tags() == [tag])
    }

    @Test("ADR 0004: duplicates from sync show once, as the latest change, and a change keeps the rest of it")
    func duplicatesShowOnceAndChangeTheLatest() throws {
        try insertRecord(id: "a", name: "Old", modifiedAfter: 1, isArchived: true)
        try insertRecord(id: "a", name: "New", modifiedAfter: 2)

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "New")])

        try library.rename(id: "a", to: "Renamed")

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "Renamed")])
    }

    @Test("ADR 0006: a tag a newer version wrote can't be renamed or archived, so this version can't damage it")
    func newerVersionIsReadOnly() throws {
        try insertRecord(id: "a", name: "Étude", modifiedAfter: 1, version: 2)

        #expect(throws: RecordFromNewerVersion.self) { try self.library.rename(id: "a", to: "Etude") }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.setArchived(true, id: "a") }
        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "Étude")])
    }

    @Test("ADR 0006: a kind this version doesn't know reads as the default, a piece")
    func unknownKindReadsAsPiece() throws {
        try insertRecord(id: "a", name: "Hanon No. 1", modifiedAfter: 1, kind: "exercise")

        #expect(try library.tags().map(\.kind) == [.piece])
    }

    @Test("TAG-1: a store written before tags existed, as on the owner's iPhone, still opens with its session")
    func storeFromBeforeTagsOpens() throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "history-before-tags", withExtension: "store", subdirectory: "Fixtures"))
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: storeURL)
        let store = HistoryStore(url: storeURL)
        // The session in the fixture, written by the app before tags existed.
        let start = Date(timeIntervalSinceReferenceDate: 820_454_400.25)
        let id = try #require(UUID(uuidString: "3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90"))
        var expected = PracticeSession(id: id, startedAt: start, timeZone: TimeZone(identifier: "Europe/Vienna"))
        try expected.pause(at: start + 300.25)
        try expected.resume(at: start + 360.5)
        try expected.stop(at: start + 1_800.625)

        #expect(try SwiftDataSessionHistory(store: store, clock: clock).sessions() == [expected])
        #expect(try SwiftDataTagLibrary(store: store, clock: clock).tags().isEmpty)
    }

    private func records() throws -> [TagRecord] {
        try ModelContext(HistoryStore(url: storeURL).container()).fetch(FetchDescriptor<TagRecord>())
    }

    /// Inserts a record as sync would deliver it, bypassing the library.
    private func insertRecord(
        id: String, name: String, modifiedAfter modified: TimeInterval, kind: String = "piece", version: Int = 1,
        isArchived: Bool = false
    ) throws {
        let context = ModelContext(try HistoryStore(url: storeURL).container())
        let record = TagRecord()
        record.id = id
        record.kind = kind
        record.name = name
        record.modifiedAt = clock.now + modified
        record.version = version
        record.isArchived = isArchived
        context.insert(record)
        try context.save()
    }
}
