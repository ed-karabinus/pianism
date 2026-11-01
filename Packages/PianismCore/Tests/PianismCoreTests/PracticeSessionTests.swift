import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct PracticeSessionTests {
    let clock = ManualClock()

    // MARK: SES-1: start and stop

    @Test("SES-1: a new session is running with no elapsed time")
    func newSessionIsRunning() {
        let session = PracticeSession(startedAt: clock.now)

        #expect(session.state == .running)
        #expect(session.elapsed(at: clock.now) == 0)
    }

    @Test("SES-1: elapsed time follows the clock while running")
    func elapsedFollowsClock() {
        let session = PracticeSession(startedAt: clock.now)

        clock.advance(by: 75)

        #expect(session.elapsed(at: clock.now) == 75)
    }

    @Test("SES-1: stopping records the end time and freezes elapsed time")
    func stopFreezesElapsed() throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 600)

        try session.stop(at: clock.now)
        let stoppedAt = clock.now
        clock.advance(by: 3_600)

        #expect(session.state == .ended)
        #expect(session.endedAt == stoppedAt)
        #expect(session.elapsed(at: clock.now) == 600)
    }

    // MARK: SES-2: pause and resume

    @Test("SES-2: paused time is excluded from elapsed time")
    func pausedTimeExcluded() throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 300)
        try session.pause(at: clock.now)
        clock.advance(by: 120)

        #expect(session.state == .paused)
        #expect(session.elapsed(at: clock.now) == 300)

        try session.resume(at: clock.now)
        clock.advance(by: 60)

        #expect(session.state == .running)
        #expect(session.elapsed(at: clock.now) == 360)
    }

    @Test("SES-2: pause and resume work any number of times", arguments: [1, 2, 10])
    func repeatedPauses(times: Int) throws {
        var session = PracticeSession(startedAt: clock.now)

        for _ in 0..<times {
            clock.advance(by: 100)  // practice
            try session.pause(at: clock.now)
            clock.advance(by: 30)  // break
            try session.resume(at: clock.now)
        }
        try session.stop(at: clock.now)

        #expect(session.pauses.count == times)
        #expect(session.elapsed(at: clock.now) == TimeInterval(100 * times))
    }

    @Test("SES-2: stopping while paused excludes the open pause")
    func stopWhilePaused() throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 900)
        try session.pause(at: clock.now)
        clock.advance(by: 300)

        try session.stop(at: clock.now)

        #expect(session.endedAt == clock.now)
        #expect(session.pauses.last?.end == clock.now)
        #expect(session.elapsed(at: clock.now) == 900)
    }

    // MARK: TAG-2: tags

    @Test("TAG-2: a running or paused session can be tagged, and its tags replaced", arguments: [false, true])
    func tagsWhileRunningOrPaused(paused: Bool) throws {
        var session = PracticeSession(startedAt: clock.now)
        if paused {
            try session.pause(at: clock.now)
        }
        #expect(session.tagIDs.isEmpty)

        try session.setTags(["skill.scales", "a"])
        try session.setTags(["a", "b"])

        #expect(session.tagIDs == ["a", "b"])
    }

    @Test("TAG-2: removing every tag leaves the session as it was untagged, so history reads it back the same")
    func removingAllTagsUntags() throws {
        let untagged = PracticeSession(startedAt: clock.now)
        var session = untagged

        try session.setTags(["a"])
        try session.setTags([])

        #expect(session == untagged)
    }

    @Test("SES-5: a finished session's tags can be edited, and removing them all leaves it untagged")
    func finishedSessionTagsCanBeEdited() throws {
        var untagged = PracticeSession(startedAt: clock.now)
        try untagged.stop(at: clock.now + 600)
        var session = untagged

        try session.editTags(["skill.scales", "a"])
        #expect(session.tagIDs == ["skill.scales", "a"])
        try session.editTags([])

        #expect(session == untagged)
    }

    @Test(
        "SES-5: moving a finished session's start and end keeps pauses inside, cuts those across, drops those outside")
    func editTimesKeepsPausesInside() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        for (from, to) in [(10.0, 20.0), (30, 40), (50, 60)] {
            try session.pause(at: start + from)
            try session.resume(at: start + to)
        }
        try session.stop(at: start + 70)
        let offsets = {
            session.pauses.map { [$0.start, $0.end ?? .distantFuture].map { $0.timeIntervalSince(start) } }
        }

        try session.editTimes(start: start + 15, end: start + 55)
        #expect([session.startedAt, session.endedAt] == [start + 15, start + 55])
        #expect(offsets() == [[15, 20], [30, 40], [50, 55]])
        #expect(session.elapsed(at: .distantPast) == 20)

        try session.editTimes(start: start + 20, end: start + 50)
        #expect(offsets() == [[30, 40]])
        try session.editTimes(start: start + 30, end: start + 30)
        #expect(session.elapsed(at: .distantPast) == 0)
    }

    @Test("SES-5: a finished session's note can be edited, and clearing it leaves the session as it was")
    func finishedSessionNoteCanBeEdited() throws {
        var plain = PracticeSession(startedAt: clock.now)
        try plain.stop(at: clock.now + 600)
        var session = plain

        try session.editNote("Coda, slowly")
        #expect(session.note == "Coda, slowly")
        try session.editNote("")

        #expect(session == plain)
    }

    @Test("SES-5: finished sessions share the practice time they overlap, leaving out either's pauses")
    func sharedPracticeLeavesOutPauses() throws {
        func finished(_ from: TimeInterval, _ to: TimeInterval, pausedFrom: TimeInterval? = nil) throws
            -> PracticeSession
        {
            var session = PracticeSession(startedAt: clock.now + from)
            if let pausedFrom {
                try session.pause(at: clock.now + pausedFrom)
                try session.resume(at: clock.now + pausedFrom + 100)
            }
            try session.stop(at: clock.now + to)
            return session
        }
        let session = try finished(0, 600, pausedFrom: 100)
        let others = try [
            finished(150, 250), finished(120, 180), finished(600, 900), finished(-100, 1_000), finished(550, 900),
            finished(-100, 1_000, pausedFrom: 0),
        ]

        #expect(others.map(session.sharedPractice) == [50, 0, 0, 500, 50, 400])
        #expect(others.map { $0.sharedPractice(with: session) } == [50, 0, 0, 500, 50, 400])
        #expect(session.sharedPractice(with: PracticeSession(startedAt: clock.now)) == 0)
    }

    // MARK: SES-4: automatic cap

    @Test("SES-4: a running session reaches a practice time later by each pause's length")
    func whenPracticeReachesLeavesOutPauses() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        #expect(session.whenPracticeReaches(600) == start + 600)

        try session.pause(at: start + 100)
        try session.resume(at: start + 400)

        #expect(session.whenPracticeReaches(600) == start + 900)
    }

    @Test("SES-4: a paused or ended session never reaches a practice time", arguments: [false, true])
    func pausedOrEndedNeverReaches(ended: Bool) throws {
        var session = PracticeSession(startedAt: clock.now)
        if ended {
            try session.stop(at: clock.now + 60)
        } else {
            try session.pause(at: clock.now + 60)
        }

        #expect(session.whenPracticeReaches(600) == nil)
    }

    @Test("SES-4: a session already past a practice time when it last resumed reaches it then")
    func pastAtResumeReachesAtResume() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        try session.pause(at: start + 700)
        try session.resume(at: start + 800)

        #expect(session.whenPracticeReaches(600) == start + 800)
    }

    // MARK: GLN-2: where a live clock counts from

    @Test("GLN-2: a running session's practice counts from its start, and from later by each pause's length")
    func practiceOriginIsTheStartUntilAPause() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        #expect(session.practiceOrigin == start)

        try session.pause(at: start + 100)
        try session.resume(at: start + 400)
        clock.advance(by: 1_000)

        #expect(session.practiceOrigin == start + 300)
        #expect(clock.now.timeIntervalSince(session.practiceOrigin) == session.elapsed(at: clock.now))
    }

    @Test("GLN-2: a paused session's clock, stopped at the pause, reads the practice so far")
    func practiceOriginWhilePaused() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        try session.pause(at: start + 100)
        try session.resume(at: start + 400)
        try session.pause(at: start + 1_000)

        #expect(session.latestEvent.timeIntervalSince(session.practiceOrigin) == 700)
        #expect(session.elapsed(at: start + 5_000) == 700)
    }

    @Test("GLN-2: an ended session's clock, stopped at its end, reads its practice")
    func practiceOriginOnceEnded() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start)
        try session.pause(at: start + 100)
        try session.resume(at: start + 200)
        try session.stop(at: start + 500)

        #expect(session.endedAt.map { $0.timeIntervalSince(session.practiceOrigin) } == 400)
    }

    // MARK: Invalid changes are rejected and leave the session untouched

    @Test("Changes in the wrong state are rejected", arguments: InvalidChange.allCases)
    func invalidChangesAreRejected(change: InvalidChange) throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 60)
        try change.prepare(&session, clock)
        let before = session

        #expect(throws: change.expectedError) {
            try change.attempt(&session, clock)
        }
        #expect(session == before)
    }

    @Test("A clock reading earlier than the last change never shrinks elapsed time", arguments: [true, false])
    func elapsedWithSkewedClock(pausedAtEnd: Bool) throws {
        var session = PracticeSession(startedAt: clock.now)
        clock.advance(by: 100)
        try session.pause(at: clock.now)
        clock.advance(by: 50)
        try session.resume(at: clock.now)  // 100 s practiced so far
        if pausedAtEnd {
            try session.pause(at: clock.now)
        }

        // For example, the device clock was corrected backwards after the last change.
        let earlier = clock.now.addingTimeInterval(-30)

        #expect(session.elapsed(at: earlier) == 100)
    }

    // MARK: SES-6: restoring a session

    @Test("MIDI-1: a MIDI session keeps its last note's time until it ends, and survives a round trip with it")
    func aMIDISessionKeepsItsLastNoteUntilItEnds() throws {
        let start = clock.now
        var session = PracticeSession(startedAt: start, source: .midi)
        try session.pause(at: start + 30)
        try session.resume(at: start + 40)
        #expect(throws: SessionError.timeWentBackwards) { try session.noteLastPlayed(at: start + 35) }

        try session.noteLastPlayed(at: start + 70)
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: JSONEncoder().encode(session))

        #expect(decoded.lastNoteAt == start + 70)
        #expect(decoded == session)
        try session.stop(at: start + 75)
        #expect(session.lastNoteAt == nil)
        #expect(throws: SessionError.alreadyEnded) { try session.noteLastPlayed(at: start + 80) }
    }

    @Test("SES-6: a session paused mid-practice survives an encode and decode round trip")
    func codableRoundTrip() throws {
        var session = PracticeSession(startedAt: clock.now, timeZone: TimeZone(identifier: "Asia/Tokyo"))
        try session.setTags(["skill.scales", "3f2b8c1e-7a4d-4e9b-8c2f-1d5a6b7c8e90"])
        clock.advance(by: 200)
        try session.pause(at: clock.now)
        clock.advance(by: 50)

        let restored = try JSONDecoder().decode(
            PracticeSession.self,
            from: JSONEncoder().encode(session)
        )

        #expect(restored == session)
        #expect(restored.state == .paused)
        #expect(restored.elapsed(at: clock.now) == 200)
    }

    @Test(
        "SES-5: a session is timed unless it was added after the fact, which survives an encode and decode round trip")
    func sourceSurvivesRoundTrip() throws {
        var added = PracticeSession(startedAt: clock.now, source: .manual)
        try added.stop(at: clock.now + 600)

        let restored = try JSONDecoder().decode(PracticeSession.self, from: JSONEncoder().encode(added))

        #expect(PracticeSession(startedAt: clock.now).source == .timer)
        #expect(restored.source == .manual)
        #expect(restored == added)
    }
}

/// A change attempted in a state that doesn't allow it, and the error it must produce.
enum InvalidChange: CaseIterable, CustomTestStringConvertible {
    case pauseWhilePaused
    case resumeWhileRunning
    case pauseAfterStop
    case resumeAfterStop
    case stopAfterStop
    case tagAfterStop
    case editWhileRunning
    case editTimesWhileRunning
    case editNoteWhileRunning
    case changeDatedBeforeLastChange
    case editEndBeforeStart

    var expectedError: SessionError {
        switch self {
        case .pauseWhilePaused: .alreadyPaused
        case .resumeWhileRunning: .notPaused
        case .pauseAfterStop, .resumeAfterStop, .stopAfterStop, .tagAfterStop: .alreadyEnded
        case .editWhileRunning, .editTimesWhileRunning, .editNoteWhileRunning: .notEnded
        case .changeDatedBeforeLastChange, .editEndBeforeStart: .timeWentBackwards
        }
    }

    var testDescription: String {
        switch self {
        case .pauseWhilePaused: "pause while paused"
        case .resumeWhileRunning: "resume while running"
        case .pauseAfterStop: "pause after stop"
        case .resumeAfterStop: "resume after stop"
        case .stopAfterStop: "stop after stop"
        case .tagAfterStop: "tag after stop"
        case .editWhileRunning: "edit while running"
        case .editTimesWhileRunning: "edit times while running"
        case .editNoteWhileRunning: "edit the note while running"
        case .changeDatedBeforeLastChange: "a change dated before the last change"
        case .editEndBeforeStart: "an edit that ends before the start"
        }
    }

    func prepare(_ session: inout PracticeSession, _ clock: ManualClock) throws {
        switch self {
        case .pauseWhilePaused: try session.pause(at: clock.now)
        case .resumeWhileRunning, .editWhileRunning, .editTimesWhileRunning, .editNoteWhileRunning,
            .changeDatedBeforeLastChange:
            break
        case .pauseAfterStop, .resumeAfterStop, .stopAfterStop, .tagAfterStop, .editEndBeforeStart:
            try session.stop(at: clock.now)
        }
    }

    func attempt(_ session: inout PracticeSession, _ clock: ManualClock) throws {
        switch self {
        case .pauseWhilePaused, .pauseAfterStop: try session.pause(at: clock.now)
        case .resumeWhileRunning, .resumeAfterStop: try session.resume(at: clock.now)
        case .stopAfterStop: try session.stop(at: clock.now)
        case .tagAfterStop: try session.setTags(["skill.scales"])
        case .editWhileRunning: try session.editTags(["skill.scales"])
        case .editTimesWhileRunning: try session.editTimes(start: session.startedAt, end: clock.now)
        case .editNoteWhileRunning: try session.editNote("Coda")
        case .changeDatedBeforeLastChange: try session.pause(at: session.startedAt.addingTimeInterval(-1))
        case .editEndBeforeStart: try session.editTimes(start: session.startedAt + 1, end: session.startedAt)
        }
    }
}
