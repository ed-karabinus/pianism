import Foundation
import PianismCore
import PianismCoreTestSupport
import SwiftData
import Testing

@testable import PianismPersistence

/// Integration tests against a real SwiftData store in a fresh temporary directory.
final class SwiftDataSessionHistoryTests {
    // Sub-second start, to prove timestamps survive the store exactly.
    let clock = ManualClock(start: Date(timeIntervalSince1970: 1_798_761_600.123_456))
    let directory = FileManager.default.temporaryDirectory.appending(path: "SwiftDataSessionHistoryTests-\(UUID())")
    var storeURL: URL { directory.appending(path: "History/History.store") }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("HIS-1, TAG-2: saved sessions and their tags are still there when the store is opened again")
    func sessionsSurviveReopening() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var paused = PracticeSession(startedAt: clock.now, timeZone: tokyo)
        try paused.setTags(["skill.scales", "3f2b8c1e-7a4d-4e9b-8c2f-1d5a6b7c8e90"])
        try paused.pause(at: clock.now + 300.25)
        try paused.resume(at: clock.now + 360.5)
        try paused.stop(at: clock.now + 1_500.75)
        // Started before time zones were recorded, with no pauses.
        var plain = PracticeSession(startedAt: clock.now + 7_200)
        try plain.stop(at: clock.now + 9_000)

        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(paused)
        try history.save(plain)

        let reopened = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        #expect(Set(try reopened.sessions()) == [paused, plain])
    }

    @Test("ADR 0006: a session stopped while paused comes back exactly, even at a fraction of a second")
    func stoppedWhilePausedSurvivesExactly() throws {
        // The pause ends at the same instant as the session. If the store moved either time by
        // even the last bit, rebuilding the session would put the pause after the end.
        var session = PracticeSession(startedAt: clock.now)
        try session.pause(at: clock.now + 600.123_456_7)
        try session.stop(at: clock.now + 900.987_654_3)

        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(session)

        #expect(try history.sessions() == [session])
    }

    @Test("SYN-1, ADR 0006: a session whose times iCloud kept to the millisecond still reads, its pauses inside it")
    func pausesStayInsideMillisecondTimes() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        let id = UUID()
        // A pause from the very start, and one the session stopped in, each 0.4 ms outside the synced times.
        let pauses = StoredPauses(pauses: [
            .init(start: clock.now - 0.000_4, end: clock.now + 10),
            .init(start: clock.now + 595, end: clock.now + 600.000_4),
        ])
        try insertRecord(
            in: history, id: id, endingAfter: 600, modifiedAfter: 1, pauses: try JSONEncoder().encode(pauses))

        var expected = PracticeSession(id: id, startedAt: clock.now)
        try expected.pause(at: clock.now)
        try expected.resume(at: clock.now + 10)
        try expected.pause(at: clock.now + 595)
        try expected.stop(at: clock.now + 600)
        #expect(try history.sessions() == [expected])
    }

    @Test("ADR 0004: saving the same session again, even from many tasks at once, keeps one record")
    func savingTwiceKeepsOne() async throws {
        var ended = PracticeSession(startedAt: clock.now)
        try ended.stop(at: clock.now + 600)
        let session = ended
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try history.save(session) }
            }
            try await group.waitForAll()
        }

        #expect(try history.sessions() == [session])
        // Counted directly, since reading would hide a duplicate.
        #expect(try ModelContext(history.store.container()).fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    }

    @Test("ADR 0004: saving never replaces a saved session, so a stale copy from the outbox can't undo an edit")
    func savingKeepsTheSavedSession() throws {
        var saved = PracticeSession(startedAt: clock.now)
        try saved.stop(at: clock.now + 600)
        var stale = PracticeSession(id: saved.id, startedAt: clock.now)
        try stale.stop(at: clock.now + 300)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(saved)
        // Later, so a second record would win as the latest change.
        clock.advance(by: 60)

        try history.save(stale)

        #expect(try history.sessions() == [saved])
    }

    @Test("ADR 0006: a deleted session stays hidden, even when it is saved again")
    func deletedSessionStaysHidden() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(session)
        // Deleted on another device; deleting on this one arrives with SES-5.
        let context = ModelContext(try history.store.container())
        try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first).deletedAt = clock.now
        try context.save()

        try history.save(session)

        #expect(try history.sessions().isEmpty)
    }

    @Test("ADR 0004, 0006: duplicates from sync show once, as the latest change, unless any is deleted")
    func duplicatesShowOnce() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        let id = UUID()
        try insertRecord(in: history, id: id, endingAfter: 600, modifiedAfter: 2)
        try insertRecord(in: history, id: id, endingAfter: 900, modifiedAfter: 3)
        try insertRecord(in: history, id: id, endingAfter: 300, modifiedAfter: 1)
        let deleted = UUID()
        try insertRecord(in: history, id: deleted, endingAfter: 600, modifiedAfter: 2)
        try insertRecord(in: history, id: deleted, endingAfter: 600, modifiedAfter: 1, isDeleted: true)

        let sessions = try history.sessions()

        #expect(sessions.map(\.id) == [id])
        #expect(sessions.first?.endedAt == clock.now + 900)
    }

    @Test("A record that can't be rebuilt is skipped, so it can't hide the rest of history, and counted once")
    func unreadableRecordIsSkippedAndCountedOnce() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(session)
        let unreadable = Data("not JSON".utf8)
        try insertRecord(in: history, id: UUID(), endingAfter: 600, modifiedAfter: 1, pauses: unreadable)
        // Two copies of one session, as sync can leave, count once.
        let copied = UUID()
        try insertRecord(in: history, id: copied, endingAfter: 600, modifiedAfter: 1, pauses: unreadable)
        try insertRecord(in: history, id: copied, endingAfter: 600, modifiedAfter: 2, pauses: unreadable)
        // A deleted session isn't missing, so it isn't counted.
        try insertRecord(
            in: history, id: UUID(), endingAfter: 600, modifiedAfter: 1, isDeleted: true, pauses: unreadable)

        #expect(try history.sessions() == [session])
        #expect(try history.unshowableCount() == 2)
    }

    @Test("HIS-1: the end-to-end tests' unshowable sessions are skipped and counted, as a newer version's would be")
    func addedUnshowableSessions() throws {
        let store = HistoryStore(url: storeURL)
        try store.addUnshowableSessions(2)
        let history = SwiftDataSessionHistory(store: store, clock: clock)

        #expect(try history.sessions().isEmpty)
        #expect(try history.unshowableCount() == 2)
    }

    @Test("ADR 0006: pauses are stored as the JSON the ADR fixes, and the time zone by its identifier")
    func storedFormat() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var session = PracticeSession(startedAt: clock.now, timeZone: losAngeles)
        try session.pause(at: clock.now + 60)
        try session.resume(at: clock.now + 120)
        try session.stop(at: clock.now + 600)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        // Saved a while after it ended, as when it waited in the outbox.
        clock.advance(by: 700)
        try history.save(session)

        let context = ModelContext(try history.store.container())
        let record = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
        #expect(record.timeZoneID == "America/Los_Angeles")
        #expect(record.modifiedAt == clock.now)
        let json = try #require(try JSONSerialization.jsonObject(with: record.pauses) as? [String: [[String: Double]]])
        let start = session.startedAt.timeIntervalSinceReferenceDate
        #expect(json == ["pauses": [["start": start + 60, "end": start + 120]]])
    }

    @Test("A session that wouldn't read back the same is refused, so it can't hide the history")
    func refusesSessionThatWouldNotReadBack() throws {
        // Decoding skips the rules that `pause` and `stop` enforce: this pause starts before the session.
        let stored =
            #"{"id":"6B1E2A4C-0F5D-4C3B-9A8E-2D7F1C3B5A90","startedAt":820454400,"#
            + #""pauses":[{"start":820454300,"end":820454350}],"endedAt":820455000}"#
        let session = try JSONDecoder().decode(PracticeSession.self, from: Data(stored.utf8))
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)

        #expect(throws: SessionRefused.self) { try history.save(session) }
        #expect(try history.sessions().isEmpty)
    }

    @Test("ADR 0007: a store that couldn't open opens on a later call, once the cause is gone")
    func opensOnceTheCauseIsGone() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        // A file where the store's folder should be, so the folder can't be created.
        let folder = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: folder)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        #expect(throws: (any Error).self) { try history.save(session) }

        try FileManager.default.removeItem(at: folder)

        try history.save(session)
        #expect(try history.sessions() == [session])
    }

    @Test("Once open, the store is reused rather than opened again on every call")
    func opensOnce() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)

        #expect(try history.store.container() === history.store.container())
    }

    @Test("A store that can't open makes every call fail, rather than the app crash")
    func unopenableStoreFailsEachCall() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        // A folder can't be created inside a file.
        let history = SwiftDataSessionHistory(
            store: HistoryStore(url: URL(filePath: "/dev/null/History.store")), clock: clock)

        #expect(throws: (any Error).self) { try history.sessions() }
        #expect(throws: (any Error).self) { try history.save(session) }
        #expect(throws: (any Error).self) { try history.canEdit(id: session.id) }
        #expect(throws: (any Error).self) { try history.edit(session) }
    }

    @Test(
        "SES-5: an edit of tags, times and note replaces the saved session, stamped with when it changed, and survives reopening"
    )
    func editReplacesSession() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        var session = PracticeSession(startedAt: clock.now)
        try session.pause(at: clock.now + 100)
        try session.resume(at: clock.now + 200)
        try session.stop(at: clock.now + 600)
        try history.save(session)
        clock.advance(by: 3_600)
        var edited = session
        try edited.editTags(["skill.scales"])
        try edited.editTimes(start: session.startedAt + 150, end: session.startedAt + 500)
        try edited.editNote("Coda, slowly")

        #expect(try history.canEdit(id: session.id))
        try history.edit(edited)

        let reopened = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        #expect(try reopened.sessions() == [edited])
        let records = try ModelContext(reopened.store.container()).fetch(FetchDescriptor<SessionRecord>())
        #expect(records.map(\.modifiedAt) == [clock.now])
    }

    @Test(
        "ADR 0006: an edit keeps the note it didn't change, and what this version doesn't show: the source and an unknown time zone"
    )
    func editKeepsWhatItDoesntShow() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try insertRecord(in: history, id: UUID(), endingAfter: 600, modifiedAfter: 0)
        let context = ModelContext(try history.store.container())
        let record = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
        (record.note, record.source, record.timeZoneID) = ("Left hand alone", "midi", "Mars/Olympus_Mons")
        try context.save()
        var edited = try #require(try history.sessions().first)
        try edited.editTags(["skill.scales"])

        try history.edit(edited)

        let stored = try #require(
            try ModelContext(history.store.container()).fetch(FetchDescriptor<SessionRecord>()).first)
        #expect([stored.note, stored.source, stored.timeZoneID] == ["Left hand alone", "midi", "Mars/Olympus_Mons"])
        #expect(stored.tagIDs == ["skill.scales"])
    }

    @Test("ADR 0006: an edit changes the copy that shows and keeps it the latest, even with this clock behind")
    func editKeepsShownCopyLatest() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        let id = UUID()
        // From another device whose clock runs ahead, and an older copy.
        try insertRecord(in: history, id: id, endingAfter: 600, modifiedAfter: 7_200)
        try insertRecord(in: history, id: id, endingAfter: 300, modifiedAfter: 60)
        var edited = try #require(try history.sessions().first)
        try edited.editTags(["skill.scales"])

        try history.edit(edited)

        #expect(try history.sessions() == [edited])
    }

    @Test("ADR 0006: a session a newer version wrote can't be edited, and a deleted or unsaved one is left alone")
    func editRefusesNewerDeletedAndUnsaved() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        let newer = UUID()
        let deleted = UUID()
        try insertRecord(in: history, id: newer, endingAfter: 600, modifiedAfter: 0, version: 2)
        try insertRecord(in: history, id: deleted, endingAfter: 600, modifiedAfter: 0, isDeleted: true)
        let before = try history.sessions()
        var fromNewer = try #require(before.first)
        try fromNewer.editTags(["skill.scales"])
        var gone = PracticeSession(id: deleted, startedAt: clock.now)
        try gone.stop(at: clock.now + 600)
        try gone.editTags(["skill.scales"])
        var unsaved = PracticeSession(startedAt: clock.now)
        try unsaved.stop(at: clock.now + 600)

        for id in [newer, deleted, unsaved.id] {
            #expect(try !history.canEdit(id: id))
        }
        #expect(throws: RecordFromNewerVersion.self) { try history.edit(fromNewer) }
        try history.edit(gone)
        try history.edit(unsaved)

        #expect(try history.sessions() == before)
        #expect(try ModelContext(history.store.container()).fetchCount(FetchDescriptor<SessionRecord>()) == 2)
    }

    @Test(
        "SES-5, ADR 0006: deleting marks every copy deleted without its note or tags, so it stays hidden and saving it again changes nothing"
    )
    func deleteMarksEveryCopy() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        try session.editTags(["skill.scales"])
        try session.editNote("Left hand alone")
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(session)
        // A duplicate as sync would leave it, changed later than this clock.
        try insertRecord(in: history, id: session.id, endingAfter: 600, modifiedAfter: 60)
        clock.advance(by: 10)

        try history.delete(id: session.id)
        try history.save(session)

        let reopened = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        #expect(try reopened.sessions().isEmpty)
        #expect(try !reopened.canEdit(id: session.id))
        let records = try ModelContext(reopened.store.container()).fetch(FetchDescriptor<SessionRecord>())
        #expect(records.map(\.deletedAt) == [clock.now, clock.now])
        // Never earlier than before, as with an edit.
        #expect(Set(records.map(\.modifiedAt)) == [clock.now, clock.now + 50])
        #expect(records.allSatisfy { $0.note.isEmpty && $0.tagIDs.isEmpty })
    }

    @Test("ADR 0006: a session a newer version wrote can't be deleted, and deleting an unsaved one adds nothing")
    func deleteRefusesNewerAndUnsaved() throws {
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        let newer = UUID()
        try insertRecord(in: history, id: newer, endingAfter: 600, modifiedAfter: 0, version: 2)
        let before = try history.sessions()

        #expect(throws: RecordFromNewerVersion.self) { try history.delete(id: newer) }
        try history.delete(id: UUID())

        #expect(try history.sessions() == before)
        #expect(try ModelContext(history.store.container()).fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    }

    /// Inserts a record as sync would deliver it, bypassing `save`.
    private func insertRecord(
        in history: SwiftDataSessionHistory, id: UUID, endingAfter seconds: TimeInterval,
        modifiedAfter modified: TimeInterval, isDeleted: Bool = false, pauses: Data = Data(), version: Int = 1
    ) throws {
        let context = ModelContext(try history.store.container())
        let record = SessionRecord()
        record.id = id
        record.startedAt = clock.now
        record.endedAt = clock.now + seconds
        record.pauses = pauses
        record.modifiedAt = clock.now + modified
        record.deletedAt = isDeleted ? clock.now + modified : nil
        record.version = version
        context.insert(record)
        try context.save()
    }
}
