/// Where the one session that is running, or just ended, lives until it moves to history
/// (ADR 0003).
///
/// The app, a Live Activity and the widget can all change the running session, some of them from
/// separate processes. To keep them from overwriting each other, every change is a single
/// read-modify-write of the whole value through ``update(_:)``, which an implementation makes
/// atomic. `nil` means no session is running.
public protocol RunningSessionStore: Sendable {
    /// The stored session, or `nil` if there is none.
    func current() throws -> PracticeSession?

    /// Reads the stored session, lets `change` modify it, and stores the result, as one step that
    /// no other change can interleave with.
    ///
    /// If `change` throws, nothing is stored and the error is rethrown. Returns what `change`
    /// returns.
    func update<Result: Sendable>(_ change: (inout PracticeSession?) throws -> Result) throws -> Result
}
