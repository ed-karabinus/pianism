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
                Tag(
                    id: ballade.id, kind: .piece, name: "Ballade No. 1 in G minor", isArchived: false, createdAt: added),
                Tag(id: pedalling.id, kind: .skill, name: "Pedalling", isArchived: true, createdAt: added),
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

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "New", isArchived: false)])

        try library.rename(id: "a", to: "Renamed")

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "Renamed", isArchived: false)])
    }

    @Test("ADR 0006: a tag a later version deleted doesn't show, even beside a newer copy, and stays deleted")
    func deletedTagStaysHidden() throws {
        try insertRecord(id: "a", name: "Old", modifiedAfter: 1, isDeleted: true)
        try insertRecord(id: "a", name: "New", modifiedAfter: 2)
        try insertRecord(id: "b", name: "Kept", modifiedAfter: 1)

        try library.rename(id: "a", to: "Renamed")

        #expect(try library.tags().map(\.id) == ["b"])
        #expect(try records().filter { $0.id == "a" }.map(\.name).sorted() == ["New", "Old"])
    }

    @Test("ADR 0006: a tag a newer version wrote can't be renamed or archived, so this version can't damage it")
    func newerVersionIsReadOnly() throws {
        try insertRecord(id: "a", name: "Étude", modifiedAfter: 1, version: 2)

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)])
        #expect(throws: RecordFromNewerVersion.self) { try self.library.rename(id: "a", to: "Etude") }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.setArchived(true, id: "a") }
        #expect(try library.tags().map(\.name) == ["Étude"])
    }

    @Test("ADR 0004: a tag merged on another device says which tag it was merged into")
    func mergedIntoIsRead() throws {
        try insertRecord(id: "a", name: "Ballade", modifiedAfter: 1, mergedInto: "b")
        try insertRecord(id: "b", name: "Ballade No. 1", modifiedAfter: 1)

        let tags = Dictionary(uniqueKeysWithValues: try library.tags().map { ($0.id, $0) })

        #expect(tags["a"]?.mergedInto == "b")
        #expect(tags["b"]?.mergedInto == nil)
    }

    @Test("ADR 0006: a kind this version doesn't know reads as the default, a piece")
    func unknownKindReadsAsPiece() throws {
        try insertRecord(id: "a", name: "Hanon No. 1", modifiedAfter: 1, kind: "exercise")

        #expect(try library.tags().map(\.kind) == [.piece])
    }

    private func records() throws -> [TagRecord] {
        try ModelContext(HistoryStore(url: storeURL).container()).fetch(FetchDescriptor<TagRecord>())
    }

    /// Inserts a record as sync would deliver it, bypassing the library.
    private func insertRecord(
        id: String, name: String, modifiedAfter modified: TimeInterval, kind: String = "piece", version: Int = 1,
        isArchived: Bool = false, mergedInto: String = "", isDeleted: Bool = false
    ) throws {
        let context = ModelContext(try HistoryStore(url: storeURL).container())
        let record = TagRecord()
        record.id = id
        record.kind = kind
        record.name = name
        record.modifiedAt = clock.now + modified
        record.version = version
        record.isArchived = isArchived
        record.mergedInto = mergedInto
        record.deletedAt = isDeleted ? clock.now + modified : nil
        context.insert(record)
        try context.save()
    }
}
