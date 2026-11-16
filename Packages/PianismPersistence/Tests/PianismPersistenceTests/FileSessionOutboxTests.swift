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

    @Test("SES-5: removing a session that isn't waiting is harmless, so deleting a saved one can always try")
    func removingAbsentIsHarmless() throws {
        let session = try endedSession(startingAfter: 0)
        try outbox.remove(id: session.id)
        try outbox.add(session)

        try outbox.remove(id: UUID())

        #expect(try outbox.sessions() == [session])
    }

    @Test("No folder means nothing is waiting")
    func noFolderNothingWaiting() throws {
        #expect(try outbox.sessions().isEmpty)
        #expect(outbox.unreadableCount() == 0)
    }

    @Test("ADR 0007: a waiting file that can't be read moves aside, so it can't hold back the rest")
    func unreadableFileMovesAside() throws {
        let session = try endedSession(startingAfter: 0)
        try outbox.add(session)
        let name = "\(UUID().uuidString).json"
        try Data("not a session".utf8).write(to: outboxDirectory.appending(path: name))

        #expect(try outbox.sessions() == [session])
        #expect(try outbox.sessions() == [session])
        #expect(FileManager.default.fileExists(atPath: outboxDirectory.appending(path: "Unreadable/\(name)").path))
        #expect(!FileManager.default.fileExists(atPath: outboxDirectory.appending(path: name).path))
        #expect(outbox.unreadableCount() == 1)
    }

    @Test("#87: a waiting file moved aside comes back once this version can read it, as after an update")
    func readableAgainComesBack() throws {
        // Given a waiting session's file this version couldn't read, moved aside
        let session = try endedSession(startingAfter: 0)
        let name = "\(session.id.uuidString).json"
        try FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)
        try Data("from a newer version".utf8).write(to: outboxDirectory.appending(path: name))
        #expect(try outbox.sessions().isEmpty)

        // When an update can read it
        try JSONEncoder().encode(session).write(to: outboxDirectory.appending(path: "Unreadable/\(name)"))

        // Then it's waiting again, and no longer counted
        #expect(try outbox.sessions() == [session])
        #expect(outbox.unreadableCount() == 0)
        try outbox.remove(id: session.id)
        #expect(try outbox.sessions().isEmpty)
    }

    @Test("#87: a file brought back from aside doesn't replace the same session waiting again")
    func waitingAgainWinsOverAside() throws {
        // Given a session moved aside, then the same session, later, waiting again
        let session = try endedSession(startingAfter: 0)
        let name = "\(session.id.uuidString).json"
        try FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)
        try Data("from a newer version".utf8).write(to: outboxDirectory.appending(path: name))
        #expect(try outbox.sessions().isEmpty)
        var older = PracticeSession(id: session.id, startedAt: clock.now - 7_200)
        try older.stop(at: clock.now - 3_600)
        try JSONEncoder().encode(older).write(to: outboxDirectory.appending(path: "Unreadable/\(name)"))
        try outbox.add(session)

        // When the outbox is read
        let waiting = try outbox.sessions()

        // Then the one waiting again stays, and the copy aside is gone
        #expect(waiting == [session])
        #expect(outbox.unreadableCount() == 0)
    }

    @Test("A waiting file that can't be read right now stays where it is, to be retried")
    func unreadableForNowStays() throws {
        let session = try endedSession(startingAfter: 0)
        try outbox.add(session)
        let file = outboxDirectory.appending(path: "\(session.id.uuidString).json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        #expect(try outbox.sessions().isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: outboxDirectory.appending(path: "Unreadable").path))
    }

    private func endedSession(startingAfter offset: TimeInterval) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now + offset)
        try session.pause(at: clock.now + offset + 60.5)
        try session.stop(at: clock.now + offset + 900.25)
        return session
    }
}
