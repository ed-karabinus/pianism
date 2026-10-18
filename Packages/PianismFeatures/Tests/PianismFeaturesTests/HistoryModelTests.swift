import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct HistoryModelTests {
    let clock = ManualClock()
    let outbox = InMemorySessionHistory()

    @Test("ADR 0007: a session both saved and waiting shows once, as saved; one only waiting is marked")
    func savedAndWaitingShowOnce() throws {
        let history = InMemorySessionHistory()
        let both = try endedSession(startingAfter: 0)
        let waiting = try endedSession(startingAfter: 3_600)
        history.save(both)
        outbox.add(both)
        outbox.add(waiting)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)

        model.refresh()

        #expect(model.days.flatMap(\.sessions) == [waiting, both])
        #expect(model.waitingIDs == [waiting.id])
        #expect(!model.loadFailed)
    }

    @Test("ADR 0007: while history can't load, waiting sessions still show, and the failure clears once it loads")
    func waitingShowDuringFailure() throws {
        let history = FlakyHistory()
        let waiting = try endedSession(startingAfter: 0)
        outbox.add(waiting)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)

        model.refresh()

        #expect(model.loadFailed)
        #expect(model.days.flatMap(\.sessions) == [waiting])
        #expect(model.waitingIDs == [waiting.id])

        history.heal()
        model.refresh()

        #expect(!model.loadFailed)
    }

    @Test("ADR 0007: an outbox that can't be read doesn't hide the saved history")
    func unreadableOutboxKeepsHistory() throws {
        let history = InMemorySessionHistory()
        let saved = try endedSession(startingAfter: 0)
        history.save(saved)
        let model = HistoryModel(
            history: history, tags: InMemoryTagLibrary(), outbox: UnavailableOutbox(), clock: clock)

        model.refresh()

        #expect(model.days.flatMap(\.sessions) == [saved])
        #expect(!model.loadFailed)
    }

    @Test("SES-5: an added session ends when it's added, lasts 30 minutes, and reaches history only when saved")
    func addedSessionReachesHistoryOnSave() throws {
        let history = InMemorySessionHistory()
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)

        model.add()
        let editor = try #require(model.editing?.editor)

        #expect([editor.session.startedAt, editor.session.endedAt] == [clock.now - 30 * 60, clock.now])
        #expect(editor.session.timeZone == .current)
        #expect(!editor.isReadOnly && !editor.hasChanges)
        #expect(history.sessions().isEmpty)
        #expect(editor.save())
        model.refresh()
        #expect(model.days.flatMap(\.sessions) == [editor.session])
    }

    @Test("TAG-2, ADR 0004: a session shows its tags by name, a merged tag as the tag it was merged into")
    func sessionsShowTags() throws {
        let history = InMemorySessionHistory()
        var session = PracticeSession(startedAt: clock.now)
        try session.setTags(["old", BuiltInSkill.scales.rawValue, "ballade", "not-synced-yet"])
        try session.stop(at: clock.now + 600)
        history.save(session)
        let tags = InMemoryTagLibrary([
            Tag(id: "old", kind: .piece, name: "Ballade", isArchived: true, mergedInto: "ballade"),
            Tag(id: "ballade", kind: .piece, name: "Ballade No. 1", isArchived: false),
        ])
        let model = HistoryModel(history: history, tags: tags, outbox: outbox, clock: clock)

        model.refresh()

        #expect(model.tagIndex.tags(for: session.tagIDs).map(\.name) == ["Ballade No. 1", "Scales"])
    }

    @Test("HIS-1: each refresh moves today along, so a screen left open past midnight catches up")
    func refreshMovesToday() {
        let model = HistoryModel(
            history: InMemorySessionHistory(), tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        clock.advance(by: 86_400)
        #expect(model.now != clock.now)

        model.refresh()

        #expect(model.now == clock.now)
    }

    @Test("SES-5: a saved session opens for editing, and saving replaces it; one still waiting doesn't open (ADR 0007)")
    func savedSessionsOpenForEditing() throws {
        let history = InMemorySessionHistory()
        let saved = try endedSession(startingAfter: 0)
        let waiting = try endedSession(startingAfter: 3_600)
        history.save(saved)
        outbox.add(waiting)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.edit(waiting)
        #expect(model.editing == nil)
        model.edit(saved)

        #expect(model.editing?.id == saved.id)
        let editor = try #require(model.editing?.editor)
        #expect(editor.session == saved)
        editor.note = "Coda"
        #expect(editor.save())
        #expect(history.sessions().map(\.note) == ["Coda"])
    }

    private func endedSession(startingAfter seconds: TimeInterval) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now + seconds)
        try session.stop(at: clock.now + seconds + 600)
        return session
    }
}
