import Foundation
import PianismCore
import Synchronization

/// A ``PracticeGlance`` that only remembers what it was shown, for tests.
public final class InMemoryPracticeGlance: PracticeGlance {
    private let state = Mutex<
        (totals: [PracticeTotals], sessions: [PracticeSession?], caps: [TimeInterval?], saveAfter: TimeInterval?)
    >(([], [], [], nil))

    public init() {}

    /// Every totals shown so far, in order.
    public var shown: [PracticeTotals] { state.withLock { $0.totals } }

    /// Every session shown so far, in order, `nil` where there was none.
    public var shownSessions: [PracticeSession?] { state.withLock { $0.sessions } }

    /// The cap shown with each session, in the same order, `nil` where the session wasn't capped.
    public var shownCaps: [TimeInterval?] { state.withLock { $0.caps } }

    public func show(_ totals: PracticeTotals) {
        state.withLock { $0.totals.append(totals) }
    }

    /// The MIDI save shown with the last session.
    public var shownSaveAfter: TimeInterval? { state.withLock { $0.saveAfter } }

    public func show(_ session: PracticeSession?, cappedAt cap: TimeInterval?, saveAfter: TimeInterval) {
        state.withLock {
            $0.sessions.append(session)
            $0.caps.append(cap)
            $0.saveAfter = saveAfter
        }
    }
}
