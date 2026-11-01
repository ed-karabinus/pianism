import ActivityKit
import Foundation
import PianismCore

/// The running session as a Live Activity shows it (GLN-1, ADR 0010). Only the app starts, updates and ends it; the
/// extension draws it.
public struct PracticeAttributes: ActivityAttributes, Sendable {
    /// What the Live Activity shows, well under ActivityKit's 4 KB. The clock counts by itself, so only a pause, a
    /// resume or the cap changes it.
    public struct ContentState: Codable, Hashable, Sendable {
        /// What the clock counts over: from when the session's practice was zero to the moment it reaches the cap, so
        /// the clock stops at 4:00:00 by itself with no process running (SES-4).
        public let timer: ClosedRange<Date>
        /// While paused, the moment the clock stopped.
        public let pausedAt: Date?

        public init(session: PracticeSession, cappedAt cap: TimeInterval?) {
            timer = session.practiceClock(cap: cap)
            pausedAt = session.pausedAt
        }
    }

    /// The stored session's ID, so the app can tell the activity for the session from one left over after a kill.
    public let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
