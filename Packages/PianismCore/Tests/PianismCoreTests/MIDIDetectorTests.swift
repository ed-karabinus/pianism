import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct MIDIDetectorTests {
    let start = Date(timeIntervalSinceReferenceDate: 820_454_400)

    // MARK: MIDI-1: three notes start a session

    @Test("MIDI-1: one key struck starts no session, and Stop then changes nothing")
    func oneKeyPressDoesNotStartASession() {
        var detector = MIDIDetector()

        #expect(detector.handle(.noteOn(start)).isEmpty)
        #expect(detector.handle(.stop(start + 1)).isEmpty)
    }

    @Test("MIDI-1: three notes within 10 s start a session at the first of them, and later notes start no other")
    func threeNotesInTenSecondsStartAtTheFirstNote() {
        var detector = MIDIDetector()

        #expect(detector.handle(.noteOn(start)).isEmpty)
        #expect(detector.handle(.noteOn(start + 5)).isEmpty)
        #expect(detector.handle(.noteOn(start + 9.999)) == [.start(at: start)])
        #expect(detector.handle(.noteOn(start + 10)).isEmpty)
    }

    @Test(
        "MIDI-1: notes 10 s apart or more start nothing, until three fall within 10 s, starting at the first of those")
    func threeNotesSpreadOverMoreThanTenSecondsDont() {
        var detector = MIDIDetector()

        for offset in [0, 5, 10] as [TimeInterval] {
            #expect(detector.handle(.noteOn(start + offset)).isEmpty)
        }
        #expect(detector.handle(.noteOn(start + 14)) == [.start(at: start + 5)])
    }

    @Test("MIDI-1: a chord counts one note per key, so three keys struck together start a session at that moment")
    func aChordCountsOneNotePerKey() {
        var detector = MIDIDetector()

        let effects = (1...3).flatMap { _ in detector.handle(.noteOn(start)) }

        #expect(effects == [.start(at: start)])
    }

    @Test("MIDI-1: notes dated after a new one, as before the clock stepped back, don't count toward a start")
    func notesDatedAfterTheNewOneDontCountTowardAStart() {
        var detector = MIDIDetector()
        _ = detector.handle(.noteOn(start + 60))
        _ = detector.handle(.noteOn(start + 61))

        #expect(detector.handle(.noteOn(start)).isEmpty)
        #expect(detector.handle(.noteOn(start + 1)).isEmpty)
        #expect(detector.handle(.noteOn(start + 2)) == [.start(at: start)])
    }

    // MARK: MIDI-R4: Stop

    @Test(
        "MIDI-R4: Stop ends a MIDI session at the earlier of the tap and 5 s after its last note",
        arguments: [(tappedAfter: 2.0, endsAfter: 2.0), (30, 5)])
    func stopEndsAtTheEarlierOfTheTapAndLastNotePlusFive(tappedAfter: TimeInterval, endsAfter: TimeInterval) {
        var detector = MIDIDetector()
        for _ in 1...3 { _ = detector.handle(.noteOn(start)) }
        _ = detector.handle(.noteOn(start + 70))
        // Dated earlier, as after the clock stepped back, so it doesn't move the last note back.
        _ = detector.handle(.noteOn(start + 60))

        let effects = detector.handle(.stop(start + 70 + tappedAfter))

        #expect(effects == [.end(afterLastNote: start + 70, at: start + 70 + endsAfter)])
        #expect(detector.handle(.stop(start + 100)).isEmpty)
    }

    // MARK: MIDI-1: a silence pauses, a note resumes, a longer silence ends

    @Test(
        "MIDI-1: a silence pauses the session at its last note after a minute, and not before",
        arguments: [59.0, 60, 61])
    func silencePausesAfterAMinute(silence: TimeInterval) {
        var detector = playing(lastNote: start)

        let effects = detector.handle(.tick(start + silence))

        #expect(effects == (silence < 60 ? [] : [.pause(at: start)]))
        #expect(detector.isPausedBySilence == (silence >= 60))
    }

    @Test(
        "MIDI-1: the next deadline is a minute after the last note, then 10 minutes after the pause, and a tick at it acts"
    )
    func aTickAtTheDeadlineActs() throws {
        var detector = MIDIDetector()
        #expect(detector.nextDeadline == nil)
        // A date that doesn't add up evenly, so the tick must compare exactly as the deadline was worked out.
        for _ in 1...3 { _ = detector.handle(.noteOn(start + 0.1)) }
        let pause = try #require(detector.nextDeadline)
        #expect(pause == start + 0.1 + 60)

        #expect(detector.handle(.tick(pause)) == [.pause(at: start + 0.1)])
        let save = try #require(detector.nextDeadline)
        #expect(save == start + 0.1 + 600)
        #expect(detector.handle(.tick(save)) == [.end(afterLastNote: start + 0.1, at: start + 5.1)])
        #expect(detector.nextDeadline == nil)
    }

    @Test("MIDI-1: a note resumes a paused session at that note, or at the pause if it's dated before it")
    func aNoteResumesThePausedSession() {
        var detector = paused(since: start)
        #expect(detector.handle(.noteOn(start + 90)) == [.resume(at: start + 90)])
        #expect(detector.handle(.tick(start + 149)).isEmpty)

        // As after the clock stepped back.
        var stepped = paused(since: start)
        #expect(stepped.handle(.noteOn(start - 30)) == [.resume(at: start)])
    }

    @Test("MIDI-1: 10 minutes of silence end the session 5 s after its last note, paused first or not")
    func tenMinutesOfSilenceEndTheSession() {
        var ticked = paused(since: start)
        #expect(ticked.handle(.tick(start + 599)).isEmpty)
        #expect(ticked.handle(.tick(start + 600)) == [.end(afterLastNote: start, at: start + 5)])

        var unticked = playing(lastNote: start)
        #expect(unticked.handle(.tick(start + 1800)) == [.end(afterLastNote: start, at: start + 5)])
        #expect(unticked.handle(.stop(start + 1801)).isEmpty)
    }

    @Test("MIDI-R3: a note that arrives after the silence, as when the app comes back, can't fill it")
    func aLateNoteCantFillTheSilence() {
        var afterAPause = playing(lastNote: start)
        #expect(afterAPause.handle(.noteOn(start + 61)) == [.pause(at: start), .resume(at: start + 61)])

        // Half an hour away ends the session, and the note counts toward the next one.
        var afterHalfAnHour = playing(lastNote: start)
        #expect(afterHalfAnHour.handle(.noteOn(start + 1800)) == [.end(afterLastNote: start, at: start + 5)])
        #expect(afterHalfAnHour.handle(.noteOn(start + 1801)).isEmpty)
        #expect(afterHalfAnHour.handle(.noteOn(start + 1802)) == [.start(at: start + 1800)])
    }

    @Test("MIDI-R4: Stop while paused by a silence ends the session at once, 5 s after its last note")
    func stopWhilePausedEndsAtOnce() {
        var detector = paused(since: start)

        #expect(detector.handle(.stop(start + 90)) == [.end(afterLastNote: start, at: start + 5)])
    }

    @Test("MIDI-1: a tapped Pause left alone for 10 minutes ends the session 5 s after the tap")
    func aTappedPauseEndsAfterTheSaveTimeout() throws {
        var session = PracticeSession(startedAt: start, source: .midi)
        try session.pause(at: start + 92)
        var detector = playing(lastNote: start + 80)
        detector.sync(with: session)

        #expect(detector.nextDeadline == start + 692)
        #expect(detector.handle(.tick(start + 692)) == [.end(afterLastNote: start + 92, at: start + 97)])
    }

    @Test("MIDI-1: if the store refused the pause, the session still running plays on from the last note")
    func aRefusedPauseKeepsTheLastNote() {
        var detector = paused(since: start + 30)

        detector.sync(with: PracticeSession(startedAt: start, source: .midi))

        #expect(!detector.isPausedBySilence)
        #expect(detector.nextDeadline == start + 90)
    }

    @Test(
        "MIDI-1: a pause stays one the silence made while the stored session shows it, and not once it's paused again elsewhere"
    )
    func aSilencePauseSurvivesARefresh() throws {
        var session = PracticeSession(startedAt: start, source: .midi)
        var detector = playing(lastNote: start + 30)
        _ = detector.handle(.tick(start + 90))
        try session.pause(at: start + 30)

        detector.sync(with: session)
        #expect(detector.isPausedBySilence)

        // Resumed and paused again by another process sharing the store, as the widget will, while the app was away.
        try session.resume(at: start + 100)
        try session.pause(at: start + 110)
        detector.sync(with: session)
        #expect(!detector.isPausedBySilence)
    }

    // MARK: Following the stored session

    @Test(
        "MIDI-1: the detector plays a running MIDI session from its last change or note, pauses with a paused one, and is idle otherwise"
    )
    func syncFollowsTheStoredSession() throws {
        let running = PracticeSession(startedAt: start, source: .midi)
        var ended = running
        try ended.stop(at: start + 90)
        // No session, a session started by tapping, or a MIDI one history couldn't take: Stop changes nothing.
        for other in [nil, PracticeSession(startedAt: start), ended] {
            for var detector in [playing(lastNote: start + 50), paused(since: start + 50)] {
                detector.sync(with: other)
                #expect(detector.handle(.stop(start + 100)).isEmpty)
                #expect(detector.nextDeadline == nil)
            }
        }

        // After a relaunch, from its start; with a note heard after its last change, from that note.
        var relaunched = MIDIDetector()
        relaunched.sync(with: running)
        #expect(relaunched.handle(.stop(start + 2)) == [.end(afterLastNote: start, at: start + 2)])
        var later = playing(lastNote: start + 50)
        later.sync(with: running)
        #expect(later.handle(.stop(start + 52)) == [.end(afterLastNote: start + 50, at: start + 52)])
        #expect(later.lastNote == nil)

        // After a relaunch, from its stored last note, and from a later one heard since.
        var withLastNote = running
        try withLastNote.noteLastPlayed(at: start + 70)
        var stored = MIDIDetector()
        stored.sync(with: withLastNote)
        #expect(stored.lastNote == start + 70)
        var heardSince = playing(lastNote: start + 80)
        heardSince.sync(with: withLastNote)
        #expect(heardSince.lastNote == start + 80)

        // After a tapped Pause, paused at the tap: a note resumes it, and Stop ends it at once.
        var tapped = running
        try tapped.pause(at: start + 40)
        var resumed = playing(lastNote: start + 30)
        resumed.sync(with: tapped)
        #expect(!resumed.isPausedBySilence)
        #expect(resumed.handle(.noteOn(start + 45)) == [.resume(at: start + 45)])
        var stopped = playing(lastNote: start + 30)
        stopped.sync(with: tapped)
        #expect(stopped.handle(.stop(start + 42)) == [.end(afterLastNote: start + 40, at: start + 42)])

        // With no session to follow, notes toward a start are kept.
        var idle = MIDIDetector()
        _ = idle.handle(.noteOn(start))
        _ = idle.handle(.noteOn(start + 1))
        idle.sync(with: nil)
        #expect(idle.handle(.noteOn(start + 2)) == [.start(at: start)])
    }

    // MARK: The piano's recordings

    @Test(
        "MIDI-1, MIDI-R2, MIDI-R4: the piano's recordings make the sessions worked out for them, ticked at every deadline or not at all",
        arguments: Replay.all, [true, false])
    func theRecordingsMakeTheExpectedSessions(replay: Replay, ticked: Bool) throws {
        var settings = MIDISettings()
        settings.pauseAfter = replay.pauseAfter
        var detector = MIDIDetector(settings)
        let store = InMemoryRunningSessionStore()
        let recorder = SessionRecorder(store: store, clock: ManualClock())
        var sessions: [Replay.Session] = []
        func record(_ effects: [MIDIDetector.Effect]) throws {
            for effect in effects {
                switch effect {
                case .start(let date): try recorder.start(at: date)
                case .pause(let date): try recorder.pause(at: date)
                case .resume(let date): try recorder.resume(at: date)
                case .end(let lastNote, let date):
                    let ended = try recorder.end(afterLastNote: lastNote, at: date)
                    let kept = try recorder.archive(to: InMemorySessionHistory(), or: InMemorySessionHistory()) != nil
                    sessions.append(Replay.Session(ended, kept: kept))
                }
            }
        }
        // Ticked, the detector hears the time at each deadline before the next note, as with the app in front.
        // Unticked, it hears only the notes, as when they arrive after the app was away.
        func tick(until date: Date) throws {
            while ticked, let deadline = detector.nextDeadline, deadline <= date {
                try record(detector.handle(.tick(deadline)))
                try #require(detector.nextDeadline != deadline, "A tick at the deadline changed nothing")
            }
        }

        for note in try replay.notes().map(Self.date) {
            try tick(until: note)
            try record(detector.handle(.noteOn(note)))
        }
        if let stop = replay.stop.map(Self.date) {
            try tick(until: stop)
            try record(detector.handle(.stop(stop)))
        } else {
            try tick(until: .distantFuture)
            try record(detector.handle(.tick(.distantFuture)))
        }

        #expect(sessions == replay.expected)
        #expect(store.current() == nil)
    }

    /// The Note Ons of the recording `name` up to `until`.
    static func noteOns(in name: String, until: TimeInterval = .infinity) throws -> [TimeInterval] {
        try noteOns(in: name).filter { $0 <= until }
    }

    /// When the recording's Note Ons with a velocity above zero arrived, in its seconds. The recorder wrote a line
    /// per CoreMIDI packet, with its MIDI 1.0 bytes, or per event, such as a connection, which is skipped.
    private static func noteOns(in name: String) throws -> [TimeInterval] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
        var times: [TimeInterval] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let packet = try JSONDecoder().decode(Packet.self, from: Data(line.utf8))
            let bytes = try (packet.bytes?.split(separator: " ") ?? []).map { try #require(UInt8($0, radix: 16)) }
            var index = 0
            while index < bytes.count {
                // Only channel messages, each with its status byte: none of the recordings uses running status.
                let status = bytes[index]
                try #require((0x80..<0xF0).contains(status), "Not a status byte in \(line)")
                let length = (0xC0..<0xE0).contains(status) ? 1 : 2
                let data = bytes.dropFirst(index + 1).prefix(length)
                if status & 0xF0 == 0x90, data.count == 2, data.last != 0 { times.append(packet.t) }
                index += 1 + length
            }
        }
        return times
    }

    /// A time in a recording, as a date.
    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// A detector playing a session whose last note was at `lastNote`.
    private func playing(lastNote: Date) -> MIDIDetector {
        var detector = MIDIDetector()
        for _ in 1...3 { _ = detector.handle(.noteOn(lastNote)) }
        return detector
    }

    /// A detector whose session paused at `since`, its last note, after a minute's silence.
    private func paused(since: Date) -> MIDIDetector {
        var detector = playing(lastNote: since)
        _ = detector.handle(.tick(since + 60))
        return detector
    }
}

/// A line the recorder wrote.
private struct Packet: Decodable {
    let t: TimeInterval
    let bytes: String?
}

/// Notes from recordings of a Kawai CA59 (docs/device-checklist.md), some edited, replayed into the detector, then
/// Stop at `stop` or, without one, silence; all in the recordings' seconds. The expected sessions are MIDI-1's plan's
/// fixtures F1 to F12, worked out from the recordings by a separate script.
struct Replay: CustomTestStringConvertible, Sendable {
    /// A session's times in the recording's seconds, to the millisecond, as the plan gives them.
    struct Session: Equatable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let played: TimeInterval
        let pauses: Int
        let kept: Bool
    }

    let testDescription: String
    let notes: @Sendable () throws -> [TimeInterval]
    var stop: TimeInterval?
    var pauseAfter: TimeInterval = 60
    let expected: [Session]

    private static func song(until: TimeInterval = .infinity) throws -> [TimeInterval] {
        try MIDIDetectorTests.noteOns(in: "ca59-usb-two-pieces", until: until)
    }

    /// The two pieces with their break, 30.393 s from the note at 99.484 to the one at 129.877, set to `gap`.
    private static func song(breakOf gap: TimeInterval) throws -> [TimeInterval] {
        let notes = try song()
        let (before, after) = try (#require(notes.last { $0 < 100 }), #require(notes.first { $0 > 100 }))
        return notes.map { $0 > before ? $0 + gap - (after - before) : $0 }
    }

    private static func notes(_ file: String, until: TimeInterval = .infinity) -> @Sendable () throws -> [TimeInterval]
    {
        { try MIDIDetectorTests.noteOns(in: file, until: until) }
    }

    private static let songSession = Session(start: 47.705, end: 170.577, played: 117.872, pauses: 1, kept: true)

    static let all = [
        Replay(testDescription: "F1: one key, then Stop", notes: { try song(until: 16) }, stop: 16, expected: []),
        Replay(testDescription: "F2: two pieces with a 30 s break", notes: { try song() }, expected: [songSession]),
        Replay(
            testDescription: "F2: two pieces, Stop 2 s after the last note", notes: { try song() }, stop: 167.577,
            expected: [Session(start: 47.705, end: 167.577, played: 117.872, pauses: 1, kept: true)]),
        Replay(
            testDescription: "F2: two pieces, Stop 30 s after the last note", notes: { try song() }, stop: 195.577,
            expected: [songSession]),
        Replay(
            testDescription: "F3: the pedal held past the last note doesn't extend the session",
            notes: notes("ca59-bluetooth-pedal-past-the-end"),
            expected: [Session(start: 1513.931, end: 1597.678, played: 78.747, pauses: 1, kept: true)]),
        Replay(
            testDescription: "F4: a chord starts it", notes: notes("ca59-usb-chord-and-pedal"),
            expected: [Session(start: 1.044, end: 68.524, played: 62.480, pauses: 1, kept: true)]),
        Replay(
            testDescription: "F4: a chord starts it, Stop at 50 s", notes: notes("ca59-usb-chord-and-pedal", until: 50),
            stop: 50, expected: [Session(start: 1.044, end: 50, played: 48.756, pauses: 1, kept: false)]),
        Replay(
            testDescription: "F5: a 61 s break pauses at its last note and resumes at the next",
            notes: { try song(breakOf: 61) },
            expected: [Session(start: 47.705, end: 201.184, played: 87.479, pauses: 2, kept: true)]),
        Replay(
            testDescription: "F6: a 59 s break stays played time", notes: { try song(breakOf: 59) },
            expected: [Session(start: 47.705, end: 199.184, played: 146.479, pauses: 1, kept: true)]),
        Replay(
            testDescription: "F6: a break of exactly 60 s pauses", notes: { try song(breakOf: 60) },
            expected: [Session(start: 47.705, end: 200.184, played: 87.479, pauses: 2, kept: true)]),
        Replay(
            testDescription: "F7: a 15 s pause timeout leaves under a minute played",
            notes: notes("ca59-bluetooth-pedal-past-the-end"), pauseAfter: 15,
            expected: [Session(start: 1513.931, end: 1597.678, played: 55.653, pauses: 2, kept: false)]),
        Replay(
            testDescription: "F8: a second piano's notes join the session",
            notes: {
                let other = try MIDIDetectorTests.noteOns(in: "ca59-bluetooth-pedal-past-the-end", until: 1543.259)
                    .filter { $0 >= 1513.931 }
                return try (song() + other.map { $0 - 1513.931 + 140 }).sorted()
            },
            expected: [Session(start: 47.705, end: 174.328, played: 121.623, pauses: 1, kept: true)]),
        Replay(
            testDescription: "F9: the piano switching itself off, over USB, is silence",
            notes: notes("ca59-usb-auto-power-off"),
            expected: [Session(start: 45.035, end: 51.245, played: 1.209, pauses: 1, kept: false)]),
        Replay(
            testDescription: "F9: the piano switching itself off, over Bluetooth, is silence",
            notes: notes("ca59-bluetooth-auto-power-off"),
            expected: [Session(start: 12.4, end: 18.425, played: 1.025, pauses: 1, kept: false)]),
        Replay(
            testDescription: "F10: notes spread out start at the first three within 10 s",
            notes: notes("ca59-usb-spread-notes"),
            expected: [Session(start: 97.323, end: 103.171, played: 0.848, pauses: 1, kept: false)]),
        Replay(
            testDescription: "F10: notes spread out, then Stop", notes: notes("ca59-usb-spread-notes"), stop: 130,
            expected: [Session(start: 97.323, end: 103.171, played: 0.848, pauses: 1, kept: false)]),
        Replay(
            testDescription: "F11: unplugging and replugging is silence", notes: notes("ca59-usb-replug"), expected: []),
        Replay(
            testDescription: "F12: three notes half an hour after the last don't extend the session",
            notes: { try song() + [1965.577, 1965.877, 1966.177] },
            expected: [songSession, Session(start: 1965.577, end: 1971.177, played: 0.6, pauses: 1, kept: false)]),
    ]
}

extension Replay.Session {
    /// `session`'s times, rounded to the millisecond. One that hasn't ended matches none, as its end isn't a number.
    init(_ session: PracticeSession, kept: Bool) {
        func milliseconds(_ seconds: TimeInterval) -> TimeInterval { (seconds * 1000).rounded() / 1000 }
        self.init(
            start: milliseconds(session.startedAt.timeIntervalSinceReferenceDate),
            end: milliseconds(session.endedAt?.timeIntervalSinceReferenceDate ?? .nan),
            played: milliseconds(session.elapsed(at: .distantPast)), pauses: session.pauses.count, kept: kept)
    }
}
