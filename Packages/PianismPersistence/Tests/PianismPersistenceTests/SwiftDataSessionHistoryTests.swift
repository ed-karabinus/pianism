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

    @Test("HIS-1: saved sessions are still there when the store is opened again, as after a relaunch")
    func sessionsSurviveReopening() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var paused = PracticeSession(startedAt: clock.now, timeZone: tokyo)
        try paused.pause(at: clock.now + 300.25)
        try paused.resume(at: clock.now + 360.5)
        try paused.stop(at: clock.now + 1_500.75)
        // Started before time zones were recorded, with no pauses.
        var plain = PracticeSession(startedAt: clock.now + 7_200)
        try plain.stop(at: clock.now + 9_000)

        let history = try SwiftDataSessionHistory(url: storeURL)
        try history.save(paused)
        try history.save(plain)

        let reopened = try SwiftDataSessionHistory(url: storeURL)
        #expect(Set(try reopened.sessions()) == [paused, plain])
    }

    @Test("ADR 0006: a session stopped while paused comes back exactly, even at a fraction of a second")
    func stoppedWhilePausedSurvivesExactly() throws {
        // The pause ends at the same instant as the session. If the store moved either time by
        // even the last bit, rebuilding the session would put the pause after the end.
        var session = PracticeSession(startedAt: clock.now)
        try session.pause(at: clock.now + 600.123_456_7)
        try session.stop(at: clock.now + 900.987_654_3)

        let history = try SwiftDataSessionHistory(url: storeURL)
        try history.save(session)

        #expect(try history.sessions() == [session])
    }

    @Test("ADR 0004: saving the same session again, even from many tasks at once, keeps one record")
    func savingTwiceKeepsOne() async throws {
        var ended = PracticeSession(startedAt: clock.now)
        try ended.stop(at: clock.now + 600)
        let session = ended
        let history = try SwiftDataSessionHistory(url: storeURL)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try history.save(session) }
            }
            try await group.waitForAll()
        }

        #expect(try history.sessions() == [session])
    }

    @Test("ADR 0006: pauses are stored as the JSON the ADR fixes, and the time zone by its identifier")
    func storedFormat() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var session = PracticeSession(startedAt: clock.now, timeZone: losAngeles)
        try session.pause(at: clock.now + 60)
        try session.resume(at: clock.now + 120)
        try session.stop(at: clock.now + 600)
        try SwiftDataSessionHistory(url: storeURL).save(session)

        let record = try #require(try storedRecords().first)
        #expect(record.timeZoneID == "America/Los_Angeles")
        let json = try #require(try JSONSerialization.jsonObject(with: record.pauses) as? [String: [[String: Double]]])
        let start = clock.now.timeIntervalSinceReferenceDate
        #expect(json == ["pauses": [["start": start + 60, "end": start + 120]]])
    }

    /// The records in the store, read directly rather than through the adapter.
    private func storedRecords() throws -> [SessionRecord] {
        let container = try ModelContainer(
            for: Schema(versionedSchema: HistorySchemaV1.self),
            configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        )
        return try ModelContext(container).fetch(FetchDescriptor<SessionRecord>())
    }
}
