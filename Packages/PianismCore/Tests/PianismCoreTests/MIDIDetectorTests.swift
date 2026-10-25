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

    // MARK: Following the stored session

    @Test(
        "MIDI-1: the detector plays a stored MIDI session, running or paused, from its last change, and is idle otherwise"
    )
    func syncFollowsTheStoredSession() throws {
        var running = PracticeSession(startedAt: start, source: .midi)
        var ended = running
        try ended.stop(at: start + 90)
        // No session, a session started by tapping, or a MIDI one history couldn't take: Stop changes nothing.
        for other in [nil, PracticeSession(startedAt: start), ended] {
            var detector = playing(lastNote: start + 50)
            detector.sync(with: other)
            #expect(detector.handle(.stop(start + 100)).isEmpty)
        }

        // After a relaunch, from its start; after a tapped Pause, from the pause.
        var relaunched = MIDIDetector()
        relaunched.sync(with: running)
        #expect(relaunched.handle(.stop(start + 2)) == [.end(afterLastNote: start, at: start + 2)])
        try running.pause(at: start + 40)
        var paused = playing(lastNote: start + 30)
        paused.sync(with: running)
        #expect(paused.handle(.stop(start + 42)) == [.end(afterLastNote: start + 40, at: start + 42)])

        // A note after the last change is kept.
        var later = playing(lastNote: start + 50)
        later.sync(with: running)
        #expect(later.handle(.stop(start + 52)) == [.end(afterLastNote: start + 50, at: start + 52)])

        // With no session to follow, notes toward a start are kept.
        var idle = MIDIDetector()
        _ = idle.handle(.noteOn(start))
        _ = idle.handle(.noteOn(start + 1))
        idle.sync(with: nil)
        #expect(idle.handle(.noteOn(start + 2)) == [.start(at: start)])
    }

    // MARK: The piano's recordings

    @Test(
        "MIDI-1, MIDI-R4: the piano's recordings start and stop the sessions worked out for them", arguments: Replay.all
    )
    func theRecordingsStartAndStopAsExpected(replay: Replay) throws {
        let notes = try Self.noteOns(in: replay.file).filter { $0 <= replay.until }
        var detector = MIDIDetector()
        let store = InMemoryRunningSessionStore()
        let recorder = SessionRecorder(store: store, clock: ManualClock())
        let recorded = notes.map(Self.date)

        let effects = recorded.flatMap { detector.handle(.noteOn($0)) } + detector.handle(.stop(Self.date(replay.stop)))
        for effect in effects {
            switch effect {
            case .start(let date): try recorder.start(at: date)
            case .end(let lastNote, let date): try recorder.end(afterLastNote: lastNote, at: date)
            }
        }

        let ended = store.current()
        let kept = try recorder.archive(to: InMemorySessionHistory(), or: InMemorySessionHistory()) != nil
        #expect(ended.map { Replay.Session($0, kept: kept) } == replay.expected)
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
}

/// A line the recorder wrote.
private struct Packet: Decodable {
    let t: TimeInterval
    let bytes: String?
}

/// A recording of a Kawai CA59 (docs/device-checklist.md), replayed into the detector up to `until`, then Stop at
/// `stop`, both in the recording's seconds, and the session it leaves. The expected sessions are MIDI-1's plan's
/// fixtures F1, F2, F4 and F10, worked out from the recordings by a separate script.
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
    let file: String
    var until = TimeInterval.infinity
    let stop: TimeInterval
    let expected: Session?

    static let all = [
        Replay(
            testDescription: "F1: one key, then a long silence", file: "ca59-usb-two-pieces", until: 16, stop: 16,
            expected: nil),
        Replay(
            testDescription: "F2: two pieces, Stop 2 s after the last note", file: "ca59-usb-two-pieces",
            stop: 167.577, expected: Session(start: 47.705, end: 167.577, played: 117.872, pauses: 1, kept: true)),
        Replay(
            testDescription: "F2: two pieces, Stop 30 s after the last note", file: "ca59-usb-two-pieces",
            stop: 195.577, expected: Session(start: 47.705, end: 170.577, played: 117.872, pauses: 1, kept: true)),
        Replay(
            testDescription: "F4: a chord starts it, Stop at 50 s", file: "ca59-usb-chord-and-pedal", until: 50,
            stop: 50, expected: Session(start: 1.044, end: 50, played: 48.756, pauses: 1, kept: false)),
        Replay(
            testDescription: "F10: notes spread out start at the first three within 10 s",
            file: "ca59-usb-spread-notes",
            stop: 130, expected: Session(start: 97.323, end: 103.171, played: 0.848, pauses: 1, kept: false)),
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
