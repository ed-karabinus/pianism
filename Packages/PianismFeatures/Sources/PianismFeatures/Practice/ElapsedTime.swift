import Foundation

/// How practice time reads on screen and to VoiceOver.
enum ElapsedTime {
    /// "0:00", "25:03" or "1:02:03", in whole seconds.
    static func display(_ elapsed: TimeInterval) -> String {
        let duration = wholeSeconds(elapsed)
        let pattern: Duration.TimeFormatStyle.Pattern = duration < .seconds(3_600) ? .minuteSecond : .hourMinuteSecond
        return duration.formatted(.time(pattern: pattern))
    }

    /// "25 minutes, 3 seconds", for VoiceOver.
    static func spoken(_ elapsed: TimeInterval) -> String {
        wholeSeconds(elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    private static func wholeSeconds(_ elapsed: TimeInterval) -> Duration {
        .seconds(Int(max(elapsed, 0)))
    }
}
