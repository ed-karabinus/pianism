import PianismCore
import Synchronization

/// A ``PracticeGlance`` that only remembers what it was shown, for tests.
public final class InMemoryPracticeGlance: PracticeGlance {
    private let state = Mutex<(totals: [PracticeTotals], sessions: [PracticeSession?])>(([], []))

    public init() {}

    /// Every totals shown so far, in order.
    public var shown: [PracticeTotals] { state.withLock { $0.totals } }

    /// Every session shown so far, in order, `nil` where there was none.
    public var shownSessions: [PracticeSession?] { state.withLock { $0.sessions } }

    public func show(_ totals: PracticeTotals) {
        state.withLock { $0.totals.append(totals) }
    }

    public func show(_ session: PracticeSession?) {
        state.withLock { $0.sessions.append(session) }
    }
}
