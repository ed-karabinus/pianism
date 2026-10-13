import Foundation
import PianismCore

/// Overrides that make end-to-end tests repeatable. Debug builds only; release builds ignore them.
struct LaunchOptions {
    /// `PIANISM_NOW`: the clock reads this many seconds since 1970, and never moves.
    var clock: (any WallClock)?
    /// `PIANISM_RESET=1`: start with no running session.
    var reset = false

    static var current: LaunchOptions {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            var options = LaunchOptions()
            if let seconds = environment["PIANISM_NOW"].flatMap(TimeInterval.init) {
                options.clock = FixedClock(now: Date(timeIntervalSince1970: seconds))
            }
            options.reset = environment["PIANISM_RESET"] == "1"
            return options
        #else
            return LaunchOptions()
        #endif
    }
}

/// A clock that always reads the same time.
private struct FixedClock: WallClock {
    let now: Date
}
