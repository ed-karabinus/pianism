import Foundation
import PianismCore
import PianismCoreTestSupport
import PianismPersistence
import Testing

/// Integration tests against real files in a fresh temporary directory.
final class FileSessionOutboxTests {
    let clock = ManualClock(start: Date(timeIntervalSince1970: 1_798_761_600.123_456))
    let directory = FileManager.default.temporaryDirectory.appending(path: "FileSessionOutboxTests-\(UUID())")
    var outboxDirectory: URL { directory.appending(path: "Outbox") }
    var outbox: FileSessionOutbox { FileSessionOutbox(directory: outboxDirectory) }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("ADR 0007: waiting sessions are still there after a relaunch, and removing one keeps the rest")
    func sessionsSurviveAndRemoveOne() throws {
        let first = try endedSession(startingAfter: 0)
        let second = try endedSession(startingAfter: 3_600)
        try outbox.add(first)
        try outbox.add(second)

        let relaunched = outbox
        #expect(Set(try relaunched.sessions()) == [first, second])

        try relaunched.remove(id: first.id)
        #expect(try relaunched.sessions() == [second])
    }

    @Test("Adding a session again replaces it, so a repeated move leaves one copy")
    func addingAgainReplaces() throws {
        let session = try endedSession(startingAfter: 0)

        try outbox.add(session)
        try outbox.add(session)

        #expect(try outbox.sessions() == [session])
    }

    @Test("No folder means nothing is waiting")
    func noFolderNothingWaiting() throws {
        #expect(try outbox.sessions().isEmpty)
    }

    @Test("ADR 0007: a waiting file that can't be read is skipped and kept, so it can't hold back the rest")
    func unreadableFileIsSkippedAndKept() throws {
        let session = try endedSession(startingAfter: 0)
        try outbox.add(session)
        let unreadable = outboxDirectory.appending(path: "\(UUID().uuidString).json")
        try Data("not a session".utf8).write(to: unreadable)

        #expect(try outbox.sessions() == [session])
        #expect(FileManager.default.fileExists(atPath: unreadable.path))
    }

    private func endedSession(startingAfter offset: TimeInterval) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now + offset)
        try session.pause(at: clock.now + offset + 60.5)
        try session.stop(at: clock.now + offset + 900.25)
        return session
    }
}
