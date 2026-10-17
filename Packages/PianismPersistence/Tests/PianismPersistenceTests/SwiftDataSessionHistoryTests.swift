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

    @Test("A record that can't be rebuilt is skipped, so it can't hide the rest of history")
    func unreadableRecordIsSkipped() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        let history = SwiftDataSessionHistory(store: HistoryStore(url: storeURL), clock: clock)
        try history.save(session)
        try insertRecord(in: history, id: UUID(), endingAfter: 600, modifiedAfter: 1, pauses: Data("not JSON".utf8))

        #expect(try history.sessions() == [session])
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
    }

    /// Inserts a record as sync would deliver it, bypassing `save`.
    private func insertRecord(
        in history: SwiftDataSessionHistory, id: UUID, endingAfter seconds: TimeInterval,
        modifiedAfter modified: TimeInterval, isDeleted: Bool = false, pauses: Data = Data()
    ) throws {
        let context = ModelContext(try history.store.container())
        let record = SessionRecord()
        record.id = id
        record.startedAt = clock.now
        record.endedAt = clock.now + seconds
        record.pauses = pauses
        record.modifiedAt = clock.now + modified
        record.deletedAt = isDeleted ? clock.now + modified : nil
        context.insert(record)
        try context.save()
    }
}
