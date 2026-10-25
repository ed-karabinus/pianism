import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct SessionRecorderTests {
    let clock = ManualClock()
    let store = InMemoryRunningSessionStore()
    let outbox = InMemorySessionHistory()
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

    @Test("TAG-2: tags set on the running session are stored, and stay through pause and stop")
    func tagsAreStored() throws {
        try recorder.start()

        let tagged = try recorder.setTags(["skill.scales", "a"])
        #expect(store.current() == tagged)

        try recorder.pause()
        let stopped = try recorder.stop()
        #expect(stopped.tagIDs == ["skill.scales", "a"])
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

    @Test("Pause, resume, stop and tagging need a session", arguments: Command.changes)
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

        let archived = try recorder.archive(to: history, or: outbox)

        #expect(archived == ended)
        #expect(history.sessions() == [ended])
        #expect(store.current() == nil)
        #expect(throws: Never.self) { try recorder.start() }
    }

    @Test(
        "SES-1: a session with under 10 s of practice, pauses left out, is dropped quietly; 10 s is kept",
        arguments: [(practice: 9.0, paused: 0.0, kept: false), (10, 0, true), (5, 25, false)])
    func archiveDropsShortSession(practice: TimeInterval, paused: TimeInterval, kept: Bool) throws {
        let history = InMemorySessionHistory()
        try recorder.start()
        clock.advance(by: practice)
        try recorder.pause()
        clock.advance(by: paused)
        let ended = try recorder.stop()

        let archived = try recorder.archive(to: history, or: outbox)

        #expect(archived == (kept ? ended : nil))
        #expect(history.sessions() == (kept ? [ended] : []))
        #expect(outbox.sessions().isEmpty)
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

        #expect(try recorder.archive(to: history, or: outbox) == nil)
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

        try recorder.archive(to: history, or: outbox)

        #expect(history.sessions() == [ended])
        #expect(store.current() == nil)
    }

    @Test("ADR 0007: if history can't save, the ended session waits in the outbox and practice goes on")
    func archiveUsesOutboxWhenHistoryFails() throws {
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()

        let archived = try recorder.archive(to: FlakyHistory(), or: outbox)

        #expect(archived == ended)
        #expect(outbox.sessions() == [ended])
        #expect(store.current() == nil)
        #expect(throws: Never.self) { try recorder.start() }
    }

    @Test("ADR 0007: waiting sessions move into history once it can save them")
    func archiveMovesWaitingSessions() throws {
        let history = InMemorySessionHistory()
        try recorder.start()
        clock.advance(by: 60)
        let first = try recorder.stop()
        try recorder.archive(to: FlakyHistory(), or: outbox)
        clock.advance(by: 60)
        try recorder.start()
        clock.advance(by: 60)
        let second = try recorder.stop()

        try recorder.archive(to: history, or: outbox)

        #expect(Set(history.sessions()) == [first, second])
        #expect(outbox.sessions().isEmpty)
    }

    @Test(
        "ADR 0007: a session history refuses stays waiting without holding back the others, but an outage stops the move",
        arguments: [true, false])
    func refusedSessionDoesNotHoldBackOthers(refused: Bool) throws {
        var ended: [PracticeSession] = []
        for _ in 1...2 {
            try recorder.start()
            clock.advance(by: 60)
            ended.append(try recorder.stop())
            try recorder.archive(to: FlakyHistory(), or: outbox)
        }
        // The outbox lists the refused session first, so it would block the other if it stopped the loop.
        let history = RefusingHistory(refusing: ended[0].id, asOutage: !refused)

        try recorder.archive(to: history, or: outbox)

        #expect(history.saved.sessions() == (refused ? [ended[1]] : []))
        #expect(outbox.sessions() == (refused ? [ended[0]] : ended))
    }

    @Test("SES-6: if neither history nor the outbox can save, the ended session stays in the store")
    func archiveKeepsSessionWhenNothingCanSave() throws {
        try recorder.start()
        clock.advance(by: 60)
        let ended = try recorder.stop()

        #expect(throws: UnavailableOutbox.Failure.self) {
            try recorder.archive(to: FlakyHistory(), or: UnavailableOutbox())
        }

        #expect(store.current() == ended)
        #expect(throws: RecorderError.previousSessionNotSaved) { try recorder.start() }
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
            try widget.archive(to: history, or: outbox)
            try widget.start()
        }

        try app.archive(to: history, or: outbox)

        #expect(contended.base.current()?.state == .running)
        #expect(history.sessions().count == 1)
    }

    // MARK: SES-3: stopped earlier

    @Test("SES-3: a session stops at an earlier time the user picks, pauses left out, and is stored")
    func stopAtAnEarlierTime() throws {
        let start = clock.now
        try recorder.start()
        clock.advance(by: 100)
        try recorder.pause()
        clock.advance(by: 50)
        try recorder.resume()
        clock.advance(by: 7_000)

        let stopped = try recorder.stop(at: start + 1_000)

        #expect(stopped.endedAt == start + 1_000)
        #expect(stopped.elapsed(at: clock.now) == 950)
        #expect(store.current() == stopped)
    }

    // MARK: MIDI-1: changes dated by the piano's notes

    @Test("MIDI-1: starting at a date stores a running MIDI session that starts then, in the current time zone")
    func startAtADateRecordsAMIDISessionThere() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let recorder = SessionRecorder(store: store, clock: clock, timeZone: { tokyo })
        let firstNote = clock.now
        clock.advance(by: 0.6)

        let session = try recorder.start(at: firstNote)

        #expect(session.state == .running)
        #expect(session.source == .midi)
        #expect(session.startedAt == firstNote)
        #expect(session.timeZone == tokyo)
        #expect(store.current() == session)
        #expect(throws: RecorderError.alreadyStarted) { try recorder.start(at: clock.now) }
    }

    @Test(
        "MIDI-1: ending after the last note pauses there and stops at the end; a session already paused just stops",
        arguments: [false, true])
    func endAfterTheLastNotePausesThereThenStops(paused: Bool) throws {
        let start = clock.now
        try recorder.start(at: start)
        clock.advance(by: 100)
        if paused { try recorder.pause() }
        clock.advance(by: 100)

        let ended = try recorder.end(afterLastNote: start + 100, at: start + 105)

        #expect(ended.endedAt == start + 105)
        #expect(ended.pauses.map { [$0.start, $0.end] } == [[start + 100, start + 105]])
        #expect(ended.elapsed(at: clock.now) == 100)
        #expect(store.current() == ended)
    }

    @Test(
        "MIDI-1: a MIDI session under a minute of played time is dropped, and a minute is kept; a timer session needs 10 s",
        arguments: [
            (source: PracticeSession.Source.midi, practice: 59.9, kept: false), (.midi, 60, true), (.timer, 30, true),
        ])
    func archiveDropsAMIDISessionUnderAMinute(source: PracticeSession.Source, practice: TimeInterval, kept: Bool)
        throws
    {
        let history = InMemorySessionHistory()
        if source == .midi { try recorder.start(at: clock.now) } else { try recorder.start() }
        clock.advance(by: practice)
        let ended = try recorder.stop()

        let archived = try recorder.archive(to: history, or: outbox)

        #expect(archived == (kept ? ended : nil))
        #expect(history.sessions() == (kept ? [ended] : []))
        #expect(store.current() == nil)
    }

    // MARK: SES-4: automatic cap

    @Test("SES-4: a session left running ends when its practice reached the cap, pauses left out, and is stored")
    func endsAtCap() throws {
        let start = clock.now
        try recorder.start()
        clock.advance(by: 100)
        try recorder.pause()
        clock.advance(by: 50)
        try recorder.resume()
        clock.advance(by: 9_000)

        let ended = try recorder.end(atCap: 600)

        #expect(ended?.endedAt == start + 650)
        #expect(ended?.elapsed(at: clock.now) == 600)
        #expect(store.current() == ended)
    }

    @Test("SES-4: a running session ends once its practice reaches the cap, not before")
    func endsOnceReached() throws {
        try recorder.start()
        clock.advance(by: 599)

        #expect(try recorder.end(atCap: 600) == nil)
        #expect(store.current()?.state == .running)

        clock.advance(by: 1)
        #expect(try recorder.end(atCap: 600)?.endedAt == clock.now)
    }

    @Test("SES-4: a paused session is left alone however long it stays paused, and no session is no change")
    func pausedIsLeftAlone() throws {
        #expect(try recorder.end(atCap: 600) == nil)
        try recorder.start()
        clock.advance(by: 300)
        let paused = try recorder.pause()
        clock.advance(by: 86_400)

        #expect(try recorder.end(atCap: 600) == nil)
        #expect(store.current() == paused)
    }

    @Test("SES-4: a session another process paused after the cap check read it is left as that process left it")
    func capKeepsAnotherWritersChange() throws {
        let contended = ContendedStore()
        let app = SessionRecorder(store: contended, clock: clock)
        let liveActivity = SessionRecorder(store: contended.base, clock: clock)
        try app.start()
        clock.advance(by: 700)
        // While the app waits for the store, a Live Activity pauses the session.
        contended.beforeNextUpdate = { try liveActivity.pause() }

        #expect(try app.end(atCap: 600) == nil)
        #expect(contended.base.current()?.state == .paused)
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
    case pause, resume, stop, tag

    static let changes: [Command] = [.pause, .resume, .stop, .tag]

    var testDescription: String { "\(self)" }

    func run(on recorder: SessionRecorder) throws {
        switch self {
        case .pause: try recorder.pause()
        case .resume: try recorder.resume()
        case .stop: try recorder.stop()
        case .tag: try recorder.setTags(["skill.scales"])
        }
    }
}

/// A history that fails on one session: refusing it, as when it wouldn't read back the same, or, with
/// `asOutage`, as if the store had failed.
struct RefusingHistory: SessionHistory {
    let refusing: UUID
    let asOutage: Bool
    let saved = InMemorySessionHistory()

    func sessions() -> [PracticeSession] {
        saved.sessions()
    }

    func unshowableCount() -> Int { 0 }

    func save(_ session: PracticeSession) throws {
        if session.id == refusing {
            if asOutage { throw FlakyHistory.Failure() } else { throw SessionRefused() }
        }
        saved.save(session)
    }

    func canEdit(id: UUID) -> Bool { saved.canEdit(id: id) }
    func edit(_ session: PracticeSession) throws { try saved.edit(session) }
    func delete(id: UUID) throws { try saved.delete(id: id) }
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
