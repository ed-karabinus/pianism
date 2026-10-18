import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

/// The ``SessionHistory`` and ``SessionOutbox`` contracts, checked on the fake that core tests rely on.
struct InMemorySessionHistoryTests {
    let clock = ManualClock()

    @Test("As history, saving keeps the first copy of a session; as an outbox, adding replaces it")
    func savingKeepsAddingReplaces() throws {
        var first = PracticeSession(startedAt: clock.now)
        try first.stop(at: clock.now + 600)
        var second = PracticeSession(id: first.id, startedAt: clock.now)
        try second.stop(at: clock.now + 300)
        let history = InMemorySessionHistory()

        history.save(first)
        history.save(second)
        #expect(history.sessions() == [first])

        history.add(second)
        #expect(history.sessions() == [second])
    }

    @Test("SES-5, ADR 0006: an edit replaces the saved session, but not one a newer version wrote or one never saved")
    func editReplacesUnlessReadOnly() throws {
        var mine = PracticeSession(startedAt: clock.now)
        try mine.stop(at: clock.now + 600)
        var newer = PracticeSession(startedAt: clock.now + 900)
        try newer.stop(at: clock.now + 1_200)
        let history = InMemorySessionHistory(readOnlyIDs: [newer.id])
        history.save(mine)
        history.save(newer)
        #expect(history.canEdit(id: mine.id) && !history.canEdit(id: newer.id) && !history.canEdit(id: UUID()))

        var edited = mine
        try edited.editTags(["skill.scales"])
        try history.edit(edited)
        var newerEdited = newer
        try newerEdited.editTags(["skill.scales"])
        #expect(throws: RecordFromNewerVersion.self) { try history.edit(newerEdited) }
        var neverSaved = PracticeSession(startedAt: clock.now + 1_500)
        try neverSaved.stop(at: clock.now + 1_800)
        try history.edit(neverSaved)

        #expect(history.sessions() == [edited, newer])
    }

    @Test(
        "SES-5, ADR 0006: a deleted session no longer reads, can't be edited or saved again; a newer version's can't be deleted"
    )
    func deleteIsForGood() throws {
        var mine = PracticeSession(startedAt: clock.now)
        try mine.stop(at: clock.now + 600)
        var newer = PracticeSession(startedAt: clock.now + 900)
        try newer.stop(at: clock.now + 1_200)
        let history = InMemorySessionHistory(readOnlyIDs: [newer.id])
        history.save(mine)
        history.save(newer)

        try history.delete(id: mine.id)
        try history.delete(id: mine.id)
        try history.delete(id: UUID())
        #expect(throws: RecordFromNewerVersion.self) { try history.delete(id: newer.id) }
        history.save(mine)
        try history.edit(mine)

        #expect(history.sessions() == [newer])
        #expect(!history.canEdit(id: mine.id))
    }
}
