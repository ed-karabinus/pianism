import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct WallClockTests {
    @Test func manualClockStartsAtAFixedDateByDefault() {
        let clock = ManualClock()

        #expect(clock.now == Date(timeIntervalSince1970: 1_798_761_600))
    }

    @Test func manualClockOnlyMovesWhenAdvanced() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ManualClock(start: start)

        #expect(clock.now == start)
        clock.advance(by: 90)
        #expect(clock.now == start.addingTimeInterval(90))
    }

    @Test func systemClockTracksRealTime() {
        let before = Date()
        let now = SystemClock().now
        let after = Date()

        #expect(before <= now && now <= after)
    }
}
