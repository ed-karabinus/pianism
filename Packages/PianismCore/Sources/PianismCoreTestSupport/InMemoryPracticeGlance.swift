import PianismCore
import Synchronization

/// A ``PracticeGlance`` that only remembers what it was shown, for tests.
public final class InMemoryPracticeGlance: PracticeGlance {
    private let state = Mutex<[PracticeTotals]>([])

    public init() {}

    /// Everything shown so far, in order.
    public var shown: [PracticeTotals] { state.withLock { $0 } }

    public func show(_ totals: PracticeTotals) {
        state.withLock { $0.append(totals) }
    }
}
