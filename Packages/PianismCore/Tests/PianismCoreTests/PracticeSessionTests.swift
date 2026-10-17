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
}

/// A change attempted in a state that doesn't allow it, and the error it must produce.
enum InvalidChange: CaseIterable, CustomTestStringConvertible {
    case pauseWhilePaused
    case resumeWhileRunning
    case pauseAfterStop
    case resumeAfterStop
    case stopAfterStop
    case tagAfterStop
    case changeDatedBeforeLastChange

    var expectedError: SessionError {
        switch self {
        case .pauseWhilePaused: .alreadyPaused
        case .resumeWhileRunning: .notPaused
        case .pauseAfterStop, .resumeAfterStop, .stopAfterStop, .tagAfterStop: .alreadyEnded
        case .changeDatedBeforeLastChange: .timeWentBackwards
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
        case .changeDatedBeforeLastChange: "a change dated before the last change"
        }
    }

    func prepare(_ session: inout PracticeSession, _ clock: ManualClock) throws {
        switch self {
        case .pauseWhilePaused: try session.pause(at: clock.now)
        case .resumeWhileRunning, .changeDatedBeforeLastChange: break
        case .pauseAfterStop, .resumeAfterStop, .stopAfterStop, .tagAfterStop: try session.stop(at: clock.now)
        }
    }

    func attempt(_ session: inout PracticeSession, _ clock: ManualClock) throws {
        switch self {
        case .pauseWhilePaused, .pauseAfterStop: try session.pause(at: clock.now)
        case .resumeWhileRunning, .resumeAfterStop: try session.resume(at: clock.now)
        case .stopAfterStop: try session.stop(at: clock.now)
        case .tagAfterStop: try session.setTags(["skill.scales"])
        case .changeDatedBeforeLastChange: try session.pause(at: session.startedAt.addingTimeInterval(-1))
        }
    }
}
