import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct SessionRecorderTests {
    let clock = ManualClock()
    let store = InMemoryRunningSessionStore()
    let recorder: SessionRecorder

    init() {
        recorder = SessionRecorder(store: store, clock: clock)
    }

    // MARK: SES-1, SES-2: every command is stored before it returns

    @Test("SES-1: starting stores a running session that starts now")
    func startStoresSession() throws {
        let session = try recorder.start()

        #expect(session.state == .running)
        #expect(session.startedAt == clock.now)
        #expect(store.current() == session)
    }

    @Test("ADR 0006: starting records the time zone the session starts in")
    func startRecordsTimeZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let recorder = SessionRecorder(store: store, clock: clock, timeZone: { tokyo })

        let session = try recorder.start()

        #expect(session.timeZone == tokyo)
        #expect(store.current()?.timeZone == tokyo)
    }

    @Test("SES-1, SES-2: pause, resume and stop are each stored with the time they happen")
    func commandsAreStored() throws {
        try recorder.start()
        clock.advance(by: 300)
        let paused = try recorder.pause()
        #expect(store.current() == paused)
        #expect(paused.state == .paused)

        clock.advance(by: 60)
        let resumed = try recorder.resume()
        #expect(store.current() == resumed)
        #expect(resumed.state == .running)

        clock.advance(by: 120)
        let stopped = try recorder.stop()
        #expect(store.current() == stopped)
        #expect(stopped.endedAt == clock.now)
        #expect(stopped.elapsed(at: clock.now) == 420)
    }

    // MARK: Rejected commands leave the stored session untouched

    @Test("SES-1: starting never overwrites a session that is running or paused", arguments: [false, true])
    func startWhileStarted(paused: Bool) throws {
        try recorder.start()
        clock.advance(by: 60)
        if paused { try recorder.pause() }
        let before = store.current()

        #expect(throws: RecorderError.alreadyStarted) { try recorder.start() }
        #expect(store.current() == before)
    }

    @Test("SES-1: starting never overwrites an ended session that hasn't moved to history")
    func startWhileEndedSessionWaits() throws {
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()

        #expect(throws: RecorderError.previousSessionNotSaved) { try recorder.start() }
        #expect(store.current() == ended)
    }

    @Test("Pause, resume and stop need a session", arguments: Command.changes)
    func changesNeedSession(command: Command) {
        #expect(throws: RecorderError.noSession) { try command.run(on: recorder) }
        #expect(store.current() == nil)
    }

    @Test("A command the session rejects stores nothing")
    func rejectedChangeStoresNothing() throws {
        try recorder.start()
        clock.advance(by: 60)
        let before = store.current()

        #expect(throws: SessionError.notPaused) { try recorder.resume() }
        #expect(store.current() == before)
    }

    // MARK: SES-6: relaunch

    @Test("SES-6: after a relaunch, a running session keeps counting from its stored start")
    func relaunchWhileRunning() throws {
        try recorder.start()
        clock.advance(by: 600)
        // The app is killed here. Five minutes later it launches with a new recorder.
        clock.advance(by: 300)
        let relaunched = SessionRecorder(store: store, clock: clock)

        let restored = try #require(try relaunched.current())

        #expect(restored.state == .running)
        #expect(restored.elapsed(at: clock.now) == 900)
    }

    @Test("SES-6: after a relaunch, a paused session still excludes the pause and can be resumed")
    func relaunchWhilePaused() throws {
        try recorder.start()
        clock.advance(by: 600)
        try recorder.pause()
        clock.advance(by: 300)
        let relaunched = SessionRecorder(store: store, clock: clock)

        let restored = try #require(try relaunched.current())
        #expect(restored.state == .paused)
        #expect(restored.elapsed(at: clock.now) == 600)

        try relaunched.resume()
        clock.advance(by: 60)
        #expect(try relaunched.current()?.elapsed(at: clock.now) == 660)
    }

    // MARK: Moving ended sessions into history

    @Test("SES-1: archiving moves an ended session into history and frees the store for a new start")
    func archiveMovesEndedSession() throws {
        let history = InMemorySessionHistory()
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()

        let archived = try recorder.archive(to: history)

        #expect(archived == ended)
        #expect(history.sessions() == [ended])
        #expect(store.current() == nil)
        #expect(throws: Never.self) { try recorder.start() }
    }

    @Test("Archiving leaves a running or paused session alone", arguments: [false, true])
    func archiveIgnoresUnfinishedSession(paused: Bool) throws {
        let history = InMemorySessionHistory()
        try recorder.start()
        clock.advance(by: 60)
        if paused { try recorder.pause() }
        let before = store.current()

        #expect(try recorder.archive(to: history) == nil)
        #expect(history.sessions().isEmpty)
        #expect(store.current() == before)
    }

    @Test("SES-6: archiving again after a crash between saving and clearing keeps one copy")
    func archiveAfterCrashKeepsOneCopy() throws {
        let history = InMemorySessionHistory()
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()
        history.save(ended)  // The app died here, before clearing the store.

        try recorder.archive(to: history)

        #expect(history.sessions() == [ended])
        #expect(store.current() == nil)
    }

    @Test("SES-6: if saving to history fails, the ended session stays in the store for the next try")
    func archiveKeepsSessionWhenSaveFails() throws {
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()

        #expect(throws: UnavailableHistory.Failure.self) { try recorder.archive(to: UnavailableHistory()) }

        #expect(store.current() == ended)
    }

    @Test("Archiving never clears a session that another writer started in the meantime")
    func archiveKeepsNewerSession() throws {
        let history = InMemorySessionHistory()
        let contended = ContendedStore()
        let app = SessionRecorder(store: contended, clock: clock)
        let widget = SessionRecorder(store: contended.base, clock: clock)
        try app.start()
        clock.advance(by: 60)
        try app.stop()
        // While the app saves to history, another process archives the session and starts a new one.
        contended.beforeNextUpdate = {
            try widget.archive(to: history)
            try widget.start()
        }

        try app.archive(to: history)

        #expect(contended.base.current()?.state == .running)
        #expect(history.sessions().count == 1)
    }

    // MARK: Two writers

    @Test("A command takes the time after another writer's change, not before it")
    func timeIsReadInsideTheUpdate() throws {
        let contended = ContendedStore()
        let app = SessionRecorder(store: contended, clock: clock)
        let liveActivity = SessionRecorder(store: contended.base, clock: clock)
        try app.start()
        clock.advance(by: 60)
        // While the app waits for the store, a Live Activity pauses the session a second later.
        contended.beforeNextUpdate = {
            clock.advance(by: 1)
            try liveActivity.pause()
        }

        let stopped = try app.stop()

        #expect(stopped.endedAt == clock.now)
        #expect(stopped.elapsed(at: clock.now) == 61)
    }

    @Test("Two recorders sharing a store see each other's changes")
    func sharedStore() throws {
        let widget = SessionRecorder(store: store, clock: clock)
        let started = try widget.start()
        clock.advance(by: 30)

        let paused = try recorder.pause()

        #expect(paused.id == started.id)
        #expect(try widget.current() == paused)
    }
}

/// A recorder command that changes an existing session.
enum Command: CustomTestStringConvertible, Sendable {
    case pause, resume, stop

    static let changes: [Command] = [.pause, .resume, .stop]

    var testDescription: String { "\(self)" }

    func run(on recorder: SessionRecorder) throws {
        switch self {
        case .pause: try recorder.pause()
        case .resume: try recorder.resume()
        case .stop: try recorder.stop()
        }
    }
}

/// A history that can't be reached, as when its store fails to open.
struct UnavailableHistory: SessionHistory {
    struct Failure: Error {}

    func sessions() throws -> [PracticeSession] {
        throw Failure()
    }

    func save(_: PracticeSession) throws {
        throw Failure()
    }
}

/// A store where another writer gets in first: `beforeNextUpdate` runs once, just before the next
/// update reads the session, as if that update had been waiting for the other process.
final class ContendedStore: RunningSessionStore, @unchecked Sendable {
    let base = InMemoryRunningSessionStore()
    var beforeNextUpdate: (() throws -> Void)?

    func current() throws -> PracticeSession? {
        base.current()
    }

    func update<Result: Sendable>(_ change: (inout PracticeSession?) throws -> Result) throws -> Result {
        if let other = beforeNextUpdate {
            beforeNextUpdate = nil
            try other()
        }
        return try base.update(change)
    }
}
