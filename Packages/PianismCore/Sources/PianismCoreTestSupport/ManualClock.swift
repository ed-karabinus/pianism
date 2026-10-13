import Foundation
import PianismCore
import Synchronization

/// A clock that moves only when a test tells it to.
///
/// Use it anywhere production code takes a ``WallClock``, then call ``advance(by:)``
/// to simulate time passing without sleeping.
public final class ManualClock: WallClock {
    private let current: Mutex<Date>

    /// Creates a clock frozen at `start`.
    ///
    /// The default start is a fixed date, so tests never depend on when they run.
    public init(start: Date = Date(timeIntervalSince1970: 1_798_761_600)) {  // 2027-01-01T00:00:00Z
        current = Mutex(start)
    }

    public var now: Date {
        current.withLock { $0 }
    }

    /// Moves the clock forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        precondition(interval >= 0, "A ManualClock never moves backwards.")
        current.withLock { $0 += interval }
    }
}
