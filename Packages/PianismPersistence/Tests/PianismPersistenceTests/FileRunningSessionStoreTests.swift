import Foundation
import PianismCore
import PianismCoreTestSupport
import PianismPersistence
import Synchronization
import Testing

/// Integration tests against real files in a fresh temporary directory.
final class FileRunningSessionStoreTests {
    // Sub-second start, to prove timestamps survive the file exactly.
    let clock = ManualClock(start: Date(timeIntervalSince1970: 1_798_761_600.123_456))
    let directory: URL
    let store: FileRunningSessionStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "FileRunningSessionStoreTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = FileRunningSessionStore(fileURL: directory.appending(path: "running-session.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("No file means no session")
    func noFileNoSession() throws {
        #expect(try store.current() == nil)
        #expect(!fileExists(store.fileURL))
    }

    @Test("SES-6: a session stored by one process is read back exactly by another")
    func sessionSurvivesInFile() throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 90.5)
        try session.pause(at: clock.now)
        try store.update { $0 = session }

        let otherProcess = FileRunningSessionStore(fileURL: store.fileURL)

        #expect(try otherProcess.current() == session)
    }

    @Test("Storing no session deletes the file")
    func clearingDeletesFile() throws {
        try store.update { $0 = PracticeSession(startedAt: clock.now) }

        try store.update { $0 = nil }

        #expect(!fileExists(store.fileURL))
        #expect(try store.current() == nil)
    }

    @Test("An update whose change throws leaves the file untouched")
    func failedUpdateLeavesFile() throws {
        try store.update { $0 = PracticeSession(startedAt: clock.now) }
        let before = try Data(contentsOf: store.fileURL)
        clock.advance(by: 60)

        #expect(throws: SessionError.alreadyPaused) {
            try store.update { stored in
                try stored?.pause(at: clock.now)
                try stored?.pause(at: clock.now)
            }
        }
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test("An unreadable file counts as no session, and the next change moves it aside instead of deleting it")
    func unreadableFileIsKept() throws {
        let garbage = Data("not a session".utf8)
        try garbage.write(to: store.fileURL)

        #expect(try store.current() == nil)

        // A change that fails moves nothing.
        #expect(throws: RecorderError.noSession) { try store.update { _ in throw RecorderError.noSession } }
        #expect(try Data(contentsOf: store.fileURL) == garbage)
        #expect(!fileExists(store.unreadableFileURL))

        let session = PracticeSession(startedAt: clock.now)
        try store.update { $0 = session }

        #expect(try store.current() == session)
        #expect(try Data(contentsOf: store.unreadableFileURL) == garbage)
    }

    @Test("A file that can't be read right now, as on a locked device, is an error, not an empty store")
    func temporarilyUnreadableFileIsAnError() throws {
        let session = PracticeSession(startedAt: clock.now)
        try store.update { $0 = session }
        try setPermissions(0o000, of: store.fileURL)
        defer { try? setPermissions(0o600, of: store.fileURL) }

        #expect(throws: CocoaError.self) { try store.current() }
        #expect(throws: CocoaError.self) { try store.update { $0 = nil } }

        try setPermissions(0o600, of: store.fileURL)
        #expect(try store.current() == session)
        #expect(!fileExists(store.unreadableFileURL))
    }

    @Test("SES-6: changes from many writers at once are never lost")
    func concurrentWritersLoseNothing() throws {
        let writers = 8
        let togglesEach = 100
        let (clock, fileURL) = (clock, store.fileURL)
        try store.update { $0 = PracticeSession(startedAt: clock.now) }
        let errors = Mutex<[any Error]>([])

        // Real threads, each with its own store, stand in for the app, the widget and Live Activities.
        // NSFileCoordinator blocks, so this deliberately avoids Swift concurrency's cooperative pool.
        DispatchQueue.concurrentPerform(iterations: writers) { _ in
            let writer = FileRunningSessionStore(fileURL: fileURL)
            for _ in 0..<togglesEach {
                do {
                    try writer.update { stored in
                        clock.advance(by: 1)
                        if stored?.state == .running {
                            try stored?.pause(at: clock.now)
                        } else {
                            try stored?.resume(at: clock.now)
                        }
                    }
                } catch {
                    errors.withLock { $0.append(error) }
                }
            }
        }

        // Every second alternates practice and pause, so exactly half of the time counts.
        let toggles = writers * togglesEach
        let session = try #require(try store.current())
        #expect(errors.withLock { $0.isEmpty })
        #expect(session.pauses.count == toggles / 2)
        #expect(session.elapsed(at: clock.now) == TimeInterval(toggles / 2))
    }

    private func setPermissions(_ permissions: Int, of url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions], ofItemAtPath: url.path(percentEncoded: false))
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
