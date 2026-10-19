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

    @Test("SES-5: an added session ends now, or, to keep clear of sessions in its 30 minutes, where they started")
    func addedSessionKeepsClearOfOthers() throws {
        let history = InMemorySessionHistory()
        // Ten minutes each: one ending now, one the half hour before it runs into, and one only touching the
        // half hour before that.
        for seconds in [-600.0, -2_700, -5_100] {
            history.save(try endedSession(startingAfter: seconds))
        }
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.add()
        let editor = try #require(model.editing?.editor)

        #expect([editor.start, editor.end] == [clock.now - 4_500, clock.now - 2_700])
    }

    @Test(
        "SES-5: a session added or edited is warned about sharing a minute or more of practice with another in History, waiting ones included"
    )
    func editorsWarnOfOverlaps() throws {
        let history = InMemorySessionHistory()
        let waiting = try endedSession(startingAfter: -600)
        let later = try endedSession(startingAfter: 3_600)
        outbox.add(waiting)
        history.save(later)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.add()
        let added = try #require(model.editing?.editor)
        #expect(added.overlap == nil)
        added.end = clock.now
        #expect(added.overlap?.session == waiting)
        #expect(added.overlap?.shared == 600)
        model.edit(later)
        let editor = try #require(model.editing?.editor)
        #expect(editor.overlap == nil)
        editor.start = clock.now - 59
        #expect(editor.overlap == nil)
        editor.start = clock.now - 60

        #expect(editor.overlap?.session == waiting)
    }

    @Test("SES-5: a deleted session hides from its day at once, but storage changes only when the deletion commits")
    func deleteHidesThenCommits() throws {
        let history = InMemorySessionHistory()
        let kept = try endedSession(startingAfter: 0)
        let deleted = try endedSession(startingAfter: 3_600)
        history.save(kept)
        history.save(deleted)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(deleted)
        model.refresh()

        #expect(model.pendingDeletion == deleted)
        #expect(model.days.map(\.total) == [600])
        #expect(Set(history.sessions()) == [kept, deleted])
        model.commitDelete()
        #expect(model.pendingDeletion == nil)
        #expect(history.sessions() == [kept])
        #expect(model.days.flatMap(\.sessions) == [kept])
        #expect(!model.isShowingDeleteError)
    }

    @Test("SES-5: undoing a deletion shows the session again and leaves storage alone")
    func undoDeleteRestores() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession(startingAfter: 0)
        history.save(session)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(session)
        model.undoDelete()
        model.commitDelete()

        #expect(model.pendingDeletion == nil)
        #expect(model.days.flatMap(\.sessions) == [session])
        #expect(history.sessions() == [session])
    }

    @Test("SES-5: deleting another session commits the earlier deletion, so only the latest can be undone")
    func secondDeleteCommitsFirst() throws {
        let history = InMemorySessionHistory()
        let first = try endedSession(startingAfter: 0)
        let second = try endedSession(startingAfter: 3_600)
        history.save(first)
        history.save(second)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(first)
        model.delete(second)

        #expect(history.sessions() == [second])
        #expect(model.pendingDeletion == second)
        #expect(model.days.isEmpty)
    }

    @Test("SES-5: deleting the session being edited closes the editor")
    func deleteClosesEditor() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession(startingAfter: 0)
        history.save(session)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()
        model.edit(session)

        model.delete(session)

        #expect(model.editing == nil)
    }

    @Test("SES-5, ADR 0006: a session a newer version wrote can't be deleted")
    func readOnlyCantBeDeleted() throws {
        let session = try endedSession(startingAfter: 0)
        let history = InMemorySessionHistory(readOnlyIDs: [session.id])
        history.save(session)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(session)

        #expect(!model.canDelete(session))
        #expect(model.pendingDeletion == nil)
        #expect(model.days.flatMap(\.sessions) == [session])
    }

    @Test(
        "SES-5, ADR 0007: deleting removes a saved session's leftover copy from the outbox, so it doesn't show again as waiting"
    )
    func deleteRemovesLeftoverCopy() throws {
        let history = InMemorySessionHistory()
        let leftover = try endedSession(startingAfter: 0)
        history.save(leftover)
        outbox.add(leftover)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(leftover)
        model.commitDelete()
        model.refresh()

        #expect(outbox.sessions().isEmpty && history.sessions().isEmpty)
        #expect(model.days.isEmpty && model.waitingIDs.isEmpty)
        #expect(!model.isShowingDeleteError)
    }

    @Test(
        "SES-5, ADR 0007: a waiting session deletes, even if an archive saved it to history before the deletion commits"
    )
    func waitingDeletesAfterArchive() throws {
        let history = InMemorySessionHistory()
        let waiting = try endedSession(startingAfter: 0)
        outbox.add(waiting)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        #expect(model.canDelete(waiting))
        model.delete(waiting)
        try SessionRecorder(store: InMemoryRunningSessionStore(), clock: clock).archive(to: history, or: outbox)
        #expect(history.sessions() == [waiting])
        model.commitDelete()
        model.refresh()

        #expect(outbox.sessions().isEmpty && history.sessions().isEmpty)
        #expect(model.days.isEmpty)
        #expect(!model.isShowingDeleteError)
    }

    @Test("SES-5, ADR 0007: a waiting session deletes even while history is down, which is why it's waiting")
    func waitingDeletesWhileHistoryDown() throws {
        let waiting = try endedSession(startingAfter: 0)
        outbox.add(waiting)
        let model = HistoryModel(history: FlakyHistory(), tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(waiting)
        model.commitDelete()

        #expect(outbox.sessions().isEmpty)
        #expect(model.days.isEmpty)
        #expect(!model.isShowingDeleteError)
    }

    @Test(
        "SES-5: deleting a saved session's leftover outbox copy while history is down shows no error, and the session shows again once history opens"
    )
    func leftoverCopyComesBackAfterOutage() throws {
        let session = try endedSession(startingAfter: 0)
        let history = FlakyHistory()
        history.saved.save(session)
        outbox.add(session)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(session)
        model.commitDelete()
        #expect(!model.isShowingDeleteError)
        history.heal()
        model.refresh()

        #expect(model.days.flatMap(\.sessions) == [session])
    }

    @Test("SES-5: if the outbox can't let a session go, nothing is deleted, and it shows again with an error")
    func outboxFailureKeepsSession() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession(startingAfter: 0)
        history.save(session)
        let model = HistoryModel(
            history: history, tags: InMemoryTagLibrary(), outbox: UnavailableOutbox(), clock: clock)
        model.refresh()

        model.delete(session)
        model.commitDelete()

        #expect(model.isShowingDeleteError)
        #expect(history.sessions() == [session])
        #expect(model.days.flatMap(\.sessions) == [session])
    }

    @Test("SES-5: if history can't delete a saved session, it shows again, saved, with an error")
    func historyFailureKeepsSession() throws {
        let history = UndeletableHistory()
        let session = try endedSession(startingAfter: 0)
        history.saved.save(session)
        outbox.add(session)
        let model = HistoryModel(history: history, tags: InMemoryTagLibrary(), outbox: outbox, clock: clock)
        model.refresh()

        model.delete(session)
        model.commitDelete()

        #expect(model.isShowingDeleteError)
        #expect(model.days.flatMap(\.sessions) == [session])
        #expect(model.waitingIDs.isEmpty)
    }

    private func endedSession(startingAfter seconds: TimeInterval) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now + seconds)
        try session.stop(at: clock.now + seconds + 600)
        return session
    }
}

/// A history that works except that it can't delete, as when its store fails to save.
private struct UndeletableHistory: SessionHistory {
    let saved = InMemorySessionHistory()

    func sessions() -> [PracticeSession] { saved.sessions() }
    func save(_ session: PracticeSession) { saved.save(session) }
    func canEdit(id: UUID) -> Bool { saved.canEdit(id: id) }
    func edit(_ session: PracticeSession) throws { try saved.edit(session) }
    func delete(id _: UUID) throws { throw FlakyHistory.Failure() }
}
