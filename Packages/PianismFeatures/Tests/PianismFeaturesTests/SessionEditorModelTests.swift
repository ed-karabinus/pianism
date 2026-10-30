import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct SessionEditorModelTests {
    let clock = ManualClock()
    let tags = InMemoryTagLibrary([Tag(id: "ballade", kind: .piece, name: "Ballade No. 1", isArchived: false)])

    @Test("SES-5, TAG-2: tags picked for a finished session reach history only when the edit is saved")
    func tagsReachHistoryOnSave() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        let editor = SessionEditorModel(session: session, history: history, now: clock.now)
        let picker = TagPickerModel(target: editor, library: tags)

        picker.toggle(try #require(picker.shown(.piece).first))
        picker.toggle(BuiltInSkill.scales.tag)
        #expect(picker.selected.map(\.name) == ["Ballade No. 1", "Scales"])
        #expect(history.sessions() == [session])

        #expect(editor.save())
        #expect(history.sessions().map(\.tagIDs) == [["ballade", BuiltInSkill.scales.rawValue]])
        #expect(!editor.isShowingError)
    }

    @Test("ADR 0006: a session a newer version wrote opens read-only; one this version wrote doesn't")
    func newerVersionOpensReadOnly() throws {
        let newer = try endedSession()
        let mine = try endedSession()
        let history = InMemorySessionHistory(readOnlyIDs: [newer.id])
        history.save(newer)
        history.save(mine)

        let newerEditor = SessionEditorModel(session: newer, history: history, now: clock.now)
        #expect(newerEditor.isReadOnly && !newerEditor.isDeleted)
        #expect(!SessionEditorModel(session: mine, history: history, now: clock.now).isReadOnly)
    }

    @Test(
        "SYN-1, #107: an edit saved after another device deleted the session says so and stays open, keeping what was typed"
    )
    func savingADeletedSessionSaysSo() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        let editor = SessionEditorModel(session: session, history: history, now: clock.now)
        editor.note = "Coda"
        try history.delete(id: session.id)

        #expect(!editor.save())
        #expect(editor.isDeleted && editor.isShowingDeleted && !editor.isShowingError)
        #expect(editor.note == "Coda")
    }

    @Test(
        "SYN-1, #107: a session deleted on another device after History showed it opens read-only, saying it was deleted"
    )
    func deletedSessionOpensSayingSo() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        try history.delete(id: session.id)

        let editor = SessionEditorModel(session: session, history: history, now: clock.now)
        #expect(editor.isReadOnly && editor.isDeleted && !editor.isShowingDeleted)
        // One being added isn't in history either, but wasn't deleted.
        #expect(
            !SessionEditorModel(session: try endedSession(), isNew: true, history: history, now: clock.now).isDeleted)
    }

    @Test("SES-5: when history can't be reached, the edit is offered, and saving it says it failed")
    func unreachableHistoryFailsOnSave() throws {
        let editor = SessionEditorModel(session: try endedSession(), history: FlakyHistory(), now: clock.now)

        #expect(!editor.isReadOnly)
        editor.note = "Coda"
        #expect(!editor.save())
        #expect(editor.isShowingError)
    }

    @Test("SES-5: moving the start past a pause and back keeps the pause, as scrolling a time picker does")
    func retimingWorksFromTheOpenedSession() throws {
        var session = PracticeSession(startedAt: clock.now)
        try session.pause(at: clock.now + 60)
        try session.resume(at: clock.now + 120)
        try session.stop(at: clock.now + 600)
        let editor = SessionEditorModel(session: session, history: InMemorySessionHistory(), now: clock.now)
        editor.setTags(["ballade"])
        editor.note = "Coda"

        editor.start = clock.now + 300
        #expect(editor.session.elapsed(at: .distantPast) == 300)
        editor.start = clock.now

        #expect(editor.session.elapsed(at: .distantPast) == 540)
        #expect([editor.tagIDs, [editor.note]] == [["ballade"], ["Coda"]])
    }

    @Test("SES-5: the end can't move before the start or past when the editor opened, but can stay where it was")
    func endStaysInRange() throws {
        let session = try endedSession()
        let editor = SessionEditorModel(session: session, history: InMemorySessionHistory(), now: clock.now + 900)

        editor.end = clock.now + 901
        editor.end = clock.now - 1
        #expect(editor.session == session)
        editor.end = clock.now + 900
        #expect(editor.end == clock.now + 900)
        let late = SessionEditorModel(session: session, history: InMemorySessionHistory(), now: clock.now)
        #expect(late.latestEnd == session.endedAt)
    }

    @Test("SES-5: a picked start or end takes the other end's seconds, keeping the length in whole minutes")
    func pickedTimesTakeTheOtherEndsSeconds() throws {
        var session = PracticeSession(startedAt: clock.now + 17)
        try session.stop(at: clock.now + 617)
        let editor = SessionEditorModel(session: session, history: InMemorySessionHistory(), now: clock.now + 900)

        editor.end = clock.now + 450  // 7:30, picked as 7 minutes
        #expect(editor.end == clock.now + 437)
        #expect(editor.start == clock.now + 17)
        editor.start = clock.now + 75  // 1:15, picked as 1 minute

        #expect(editor.start == clock.now + 77)
        #expect(editor.session.elapsed(at: .distantPast) == 360)
    }

    @Test("SES-5: a time scrolled away and back to the minute it opened in is the time it opened at")
    func scrollingBackChangesNothing() throws {
        var session = PracticeSession(startedAt: clock.now + 17)
        try session.stop(at: clock.now + 645)
        let editor = SessionEditorModel(session: session, history: InMemorySessionHistory(), now: clock.now + 900)

        editor.start = clock.now + 300  // lands at 5:45, the end's seconds
        editor.end = clock.now + 400  // lands at 6:45
        #expect(editor.hasChanges)
        editor.start = clock.now + 30  // back in the minute the start opened in
        editor.end = clock.now + 630

        #expect(!editor.hasChanges)
        #expect(editor.session == session)
    }

    @Test("SES-5: the editor has changes only while the session differs from how it opened")
    func hasChangesOnlyWhileDifferent() throws {
        let editor = SessionEditorModel(session: try endedSession(), history: InMemorySessionHistory(), now: clock.now)
        #expect(!editor.hasChanges)

        editor.note = "Coda"
        #expect(editor.hasChanges)
        editor.note = ""
        editor.setTags(["ballade"])
        #expect(editor.hasChanges)
        editor.setTags([])
        editor.start = clock.now + 60
        #expect(editor.hasChanges)
        editor.start = clock.now

        #expect(!editor.hasChanges)
    }

    @Test("SYN-1: saving an unchanged edit writes nothing, so a change synced since it opened stays")
    func unchangedSaveKeepsSyncedChange() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        let editor = SessionEditorModel(session: session, history: history, now: clock.now + 600)
        try history.edit(noted(session, "From the iPhone"))

        #expect(editor.save())
        #expect(history.sessions().map(\.note) == ["From the iPhone"])
    }

    @Test("SYN-1: saving writes only what was edited, over a change synced since it opened to the same thing")
    func saveWritesOnlyEdits() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        let editor = SessionEditorModel(session: session, history: history, now: clock.now + 600)
        editor.setTags(["ballade"])
        editor.start = clock.now + 60
        var synced = try noted(session, "From the iPhone")
        try synced.editTags([BuiltInSkill.scales.rawValue])
        try history.edit(synced)

        #expect(editor.save())
        let saved = try #require(history.sessions().first)
        #expect(saved.note == "From the iPhone")
        #expect(saved.tagIDs == ["ballade"])
        #expect(saved.startedAt == clock.now + 60)
    }

    @Test("SYN-1: saving only a note keeps the times and tags another device set after the editor opened")
    func noteOnlySaveKeepsSyncedTimesAndTags() throws {
        let history = InMemorySessionHistory()
        let session = try endedSession()
        history.save(session)
        let editor = SessionEditorModel(session: session, history: history, now: clock.now + 600)
        editor.note = "Coda"
        var synced = session
        try synced.editTimes(start: clock.now + 120, end: clock.now + 600)
        try synced.editTags([BuiltInSkill.scales.rawValue])
        try history.edit(synced)

        #expect(editor.save())
        #expect(history.sessions() == [try noted(synced, "Coda")])
    }

    private func noted(_ session: PracticeSession, _ note: String) throws -> PracticeSession {
        var noted = session
        try noted.editNote(note)
        return noted
    }

    private func endedSession() throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        return session
    }
}
