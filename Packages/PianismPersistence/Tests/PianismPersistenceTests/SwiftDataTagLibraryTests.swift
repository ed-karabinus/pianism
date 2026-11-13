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

    @Test("TAG-3: a piece's details survive reopening, stamp the change, and can be cleared")
    func detailsSurviveReopening() throws {
        let library = self.library
        let added = clock.now
        let ballade = try library.add(name: "Ballade No. 1", kind: .piece)
        clock.advance(by: 60)

        try library.setDetails(composer: "Chopin", targetTempo: 72, id: ballade.id)

        #expect(
            try self.library.tags() == [
                Tag(
                    id: ballade.id, kind: .piece, name: "Ballade No. 1", isArchived: false, createdAt: added,
                    composer: "Chopin", targetTempo: 72)
            ])
        #expect(try records().map(\.modifiedAt) == [clock.now])

        try library.setDetails(composer: "", targetTempo: nil, id: ballade.id)

        #expect(try records().map(\.composer) == [""])
        #expect(try records().map(\.targetTempo) == [nil])
    }

    @Test("TAG-3: renaming or archiving a piece keeps its details")
    func changesKeepDetails() throws {
        let ballade = try library.add(name: "Ballade No. 1", kind: .piece)
        try library.setDetails(composer: "Chopin", targetTempo: 72, id: ballade.id)

        try library.rename(id: ballade.id, to: "Ballade No. 1 in G minor")
        try library.setArchived(true, id: ballade.id)

        let tag = try #require(try library.tags().first)
        #expect(tag.composer == "Chopin" && tag.targetTempo == 72)
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

    @Test(
        "ADR 0006: a tag a newer version wrote can't be renamed, archived or given details, so this version can't damage it"
    )
    func newerVersionIsReadOnly() throws {
        try insertRecord(id: "a", name: "Étude", modifiedAfter: 1, version: 2)

        #expect(try library.tags() == [Tag(id: "a", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)])
        #expect(throws: RecordFromNewerVersion.self) { try self.library.rename(id: "a", to: "Etude") }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.setArchived(true, id: "a") }
        #expect(throws: RecordFromNewerVersion.self) {
            try self.library.setDetails(composer: "Chopin", targetTempo: 72, id: "a")
        }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.merge(id: "a", into: "b") }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.unmerge(id: "a") }
        #expect(throws: RecordFromNewerVersion.self) { try self.library.setParent(id: "a", to: "b") }
        #expect(try library.tags().map(\.name) == ["Étude"])
    }

    @Test("TAG-1: the end-to-end tests' archived piece reads as a newer version's, which this one can't change")
    func addedArchivedNewerPiece() throws {
        // Given an empty store
        let store = HistoryStore(url: storeURL)

        // When the end-to-end tests' piece is added to it
        try store.addArchivedNewerPiece(named: "Étude")

        // Then the library reads it as an archived piece, read-only, with an ID as this version writes them
        let tag = try #require(try library.tags().first)
        #expect(tag == Tag(id: tag.id, kind: .piece, name: "Étude", isArchived: true, isReadOnly: true))
        #expect(UUID(uuidString: tag.id) != nil && tag.id == tag.id.lowercased())
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

    @Test("TAG-4, ADR 0004: a merge is stored and archives the tag; undoing it restores the tag exactly")
    func mergeAndUndoAreStored() throws {
        let duplicate = try library.add(name: "Ballade", kind: .piece)
        let kept = try library.add(name: "Ballade No. 1", kind: .piece)
        try library.setDetails(composer: "Chopin", targetTempo: 72, id: duplicate.id)
        let before = try library.tags()
        clock.advance(by: 60)

        try library.merge(id: duplicate.id, into: kept.id)

        var tags = Dictionary(uniqueKeysWithValues: try library.tags().map { ($0.id, $0) })
        #expect(tags[duplicate.id]?.mergedInto == kept.id)
        #expect(tags[duplicate.id]?.isArchived == true)
        #expect(tags[kept.id]?.mergedInto == nil)
        #expect(tags[kept.id]?.isArchived == false)
        // Sync's "latest copy wins" needs a merge to count as a change.
        #expect(try records().first { $0.id == duplicate.id }?.modifiedAt == clock.now)

        try library.unmerge(id: duplicate.id)

        tags = Dictionary(uniqueKeysWithValues: try library.tags().map { ($0.id, $0) })
        #expect(Set(tags.values) == Set(before))
        #expect(try records().first { $0.id == duplicate.id }?.mergedInto == "")
    }

    @Test("TAG-4, ADR 0004: merging and undoing leave sessions as they were, which count toward the kept tag")
    func mergeNeverRewritesSessions() throws {
        let duplicate = try library.add(name: "Ballade", kind: .piece)
        let kept = try library.add(name: "Ballade No. 1", kind: .piece)
        let sessions = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        var session = PracticeSession(startedAt: clock.now)
        try session.setTags([duplicate.id])
        try session.stop(at: clock.now + 60)
        try sessions.save(session)
        let before = try sessions.sessions()

        try library.merge(id: duplicate.id, into: kept.id)

        #expect(try sessions.sessions() == before)
        #expect(TagIndex(try library.tags()).tags(for: session.tagIDs).map(\.id) == [kept.id])

        try library.unmerge(id: duplicate.id)

        #expect(try sessions.sessions() == before)
        #expect(TagIndex(try library.tags()).tags(for: session.tagIDs).map(\.id) == [duplicate.id])
    }

    @Test("TAG-4, ADR 0004: opposite merges, as two devices' would sync, settle on the tag created first")
    func oppositeMergesSettle() throws {
        let first = try library.add(name: "Ballade", kind: .piece)
        clock.advance(by: 60)
        let second = try library.add(name: "Ballade No. 1", kind: .piece)

        try library.merge(id: first.id, into: second.id)
        try library.merge(id: second.id, into: first.id)

        let index = TagIndex(try library.tags())
        #expect(index[first.id]?.id == first.id)
        #expect(index[second.id]?.id == first.id)
    }

    @Test("TAG-5, ADR 0013: a tag added inside another is one record with its parent, still there when reopened")
    func addInsideIsStored() throws {
        // Given
        let library = self.library
        let added = clock.now

        // When
        let dMinor = try library.add(name: "D minor", kind: .skill, inside: BuiltInSkill.scales.rawValue)

        // Then
        let expected = Tag(
            id: dMinor.id, kind: .skill, name: "D minor", isArchived: false, parentID: BuiltInSkill.scales.rawValue,
            createdAt: added)
        #expect(dMinor == expected)
        #expect(try self.library.tags() == [expected])
        #expect(try records().map(\.parentID) == [BuiltInSkill.scales.rawValue])
    }

    @Test("TAG-5, ADR 0013: moving a tag inside another and back is stored as a change, the top level as empty")
    func setParentIsStored() throws {
        // Given
        let ballade = try library.add(name: "Ballade No. 1", kind: .piece)
        let set = try library.add(name: "Ballades", kind: .piece)
        clock.advance(by: 60)

        // When
        try library.setParent(id: ballade.id, to: set.id)
        let inside = try records().first { $0.id == ballade.id }.map { ($0.parentID, $0.modifiedAt) }
        let readInside = try self.library.tags().first { $0.id == ballade.id }?.parentID
        clock.advance(by: 60)
        try library.setParent(id: ballade.id, to: nil)

        // Then
        #expect(inside?.0 == set.id && readInside == set.id)
        // Sync's "latest copy wins" needs a move to count as a change, as a merge does.
        #expect(inside?.1 == clock.now - 60)
        #expect(try records().first { $0.id == ballade.id }?.parentID == "")
        #expect(Set(try self.library.tags()) == [ballade, set])
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
