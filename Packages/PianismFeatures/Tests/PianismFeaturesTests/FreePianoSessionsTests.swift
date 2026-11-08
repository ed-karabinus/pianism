import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

/// PRO-2: a piano starts the first 5 sessions it saves by itself, then only with Pro. Tapping Start is always free.
@MainActor
@Suite(.serialized)  // The tests share the stand-in for the device's settings.
struct FreePianoSessionsTests {
    let clock = ManualClock()
    let history = InMemorySessionHistory()
    let pro = ProSwitch()
    let defaults = UserDefaults(suiteName: "FreePianoSessionsTests") ?? .standard

    init() {
        defaults.removePersistentDomain(forName: "FreePianoSessionsTests")
    }

    @Test("PRO-2: the 5th piano session starts, the 6th doesn't, and tapping Start still does")
    func theFifthPianoSessionStartsTheSixthDoesNot() {
        let model = makeModel(used: 4)
        #expect(model.freePianoSessionsLeft == 1)

        play(model)
        #expect(history.autoLoggedIDs().count == 5, "The 5th didn't start or wasn't saved")
        #expect(model.freePianoSessionsLeft == 0)

        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.session == nil, "A 6th piano session started")

        model.start()
        #expect(model.session?.state == .running)
        #expect(model.session?.source == .timer)
    }

    @Test("PRO-2: a piano session already started plays on, pausing and resuming, after the last free one is used")
    func aStartedSessionPlaysOn() {
        let model = makeModel(used: 4)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        // Another device's piano session syncs in, using the last free one.
        history.save(ended(.midi))
        clock.advance(by: 61)
        model.tick()
        #expect(model.session?.state == .paused)

        model.noteOn(at: clock.now)

        #expect(model.session?.state == .running, "A note didn't resume it")
    }

    @Test("PRO-2: only a saved piano session uses one: not a timer session, and not a piano run too short to save")
    func onlySavedPianoSessionsUseOne() {
        let model = makeModel(used: 4)
        model.start()
        clock.advance(by: 600)
        model.stop()
        #expect(model.lastSession?.source == .timer)

        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 601)
        model.tick()
        #expect(model.lastRunWasTooShort)

        #expect(model.freePianoSessionsLeft == 1)
    }

    @Test("PRO-2: the count is read at each piano start, so another device's session counts before any refresh")
    func countReadAtTheStart() {
        let model = makeModel(used: 4)
        #expect(model.freePianoSessionsLeft == 1)
        history.save(ended(.midi))
        // One note starts a session here, so that note's own reading decides, as the next notes would read the refresh.
        model.startNotes = 1

        model.noteOn(at: clock.now)

        #expect(model.session == nil)
        #expect(model.freePianoSessionsLeft == 0)
    }

    @Test("PRO-2: with Pro, a piano starts any session, and nothing about free ones shows; buying it lifts the limit")
    func proLiftsTheLimit() {
        let model = makeModel(used: 5)
        #expect(model.freePianoSessionsLeft == 0)

        pro.isOn = true

        #expect(model.freePianoSessionsLeft == nil)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.session?.source == .midi)
    }

    @Test("PRO-2: when history can't say, a piano still starts sessions, and nothing about free ones shows")
    func historyFailingAllowsTheStart() {
        let model = makeModel(used: 0, history: FlakyHistory())
        #expect(model.freePianoSessionsLeft == nil)

        for _ in 1...3 { model.noteOn(at: clock.now) }

        #expect(model.session?.source == .midi)
    }

    @Test("PRO-2, D6: the line shows only with a piano connected and no session")
    func theLineShowsOnlyWithAPianoAndNoSession() {
        let model = makeModel(used: 2, piano: false)
        #expect(model.freePianoSessionsLeft == nil)

        model.connectedPianos = ["MIDI KEYBOARD"]
        #expect(model.freePianoSessionsLeft == 3)

        model.start()
        #expect(model.freePianoSessionsLeft == nil)
    }

    /// A model over `history`, which holds `used` piano sessions, with a piano connected unless `piano` is false.
    private func makeModel(used: Int, history: (any SessionHistory)? = nil, piano: Bool = true) -> PracticeModel {
        for _ in 0..<used { self.history.save(ended(.midi)) }
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history ?? self.history, outbox: InMemorySessionHistory(),
            clock: clock, nudges: InMemoryNudges(), glance: InMemoryPracticeGlance(), defaults: defaults,
            nudge: 5_400, cap: 14_400, isPro: { [pro] in pro.isOn }, announce: { _ in })
        if piano { model.connectedPianos = ["MIDI KEYBOARD"] }
        return model
    }

    /// Plays a piano session long enough to save, 62 s, and leaves it until it saves itself.
    private func play(_ model: PracticeModel) {
        for _ in 1...3 { model.noteOn(at: clock.now) }
        for _ in 1...2 {
            clock.advance(by: 31)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: 601)
        model.tick()
    }

    private func ended(_ source: PracticeSession.Source) -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now - 86_400, source: source)
        try? session.stop(at: session.startedAt + 600)
        return session
    }
}

/// Whether Pro is unlocked, as the tests set it.
@MainActor
final class ProSwitch {
    var isOn = false
}
