import ActivityKit
import Foundation

/// What the practice Live Activity shows (spike #17).
struct PracticeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }
}
