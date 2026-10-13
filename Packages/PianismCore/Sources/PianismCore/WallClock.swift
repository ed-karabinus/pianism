import Foundation

/// A source of the current wall-clock time.
///
/// Anything in Pianism that needs "now" takes a `WallClock` instead of calling `Date()`,
/// so tests can control time exactly (engineering principle E3).
public protocol WallClock: Sendable {
    /// The current date and time.
    var now: Date { get }
}

/// The real clock, backed by the system time.
public struct SystemClock: WallClock {
    public init() {}

    public var now: Date { Date() }
}
