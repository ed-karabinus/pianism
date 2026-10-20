import Foundation

/// Asks "Still practicing?" from outside the app, once a running session's practice reaches the nudge, so a
/// timer left running doesn't save hours that weren't practice (SES-3).
public protocol PracticeNudges: Sendable {
    /// Whether asking for permission would show the system's prompt, which it shows only once.
    func canAskPermission() async -> Bool

    /// Asks for permission to nudge.
    func requestPermission() async

    /// Nudges about the session with this ID after `delay` seconds, replacing any nudge still waiting. A delay
    /// rather than a date, as the app's clock may be fixed while the system's runs on.
    func schedule(after delay: TimeInterval, sessionID: UUID)

    /// Cancels the nudge still waiting, if there is one.
    func cancel()
}
