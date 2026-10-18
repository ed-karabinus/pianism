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

        #expect(SessionEditorModel(session: newer, history: history, now: clock.now).isReadOnly)
        #expect(!SessionEditorModel(session: mine, history: history, now: clock.now).isReadOnly)
    }

    @Test("SES-5: when history can't be reached, the edit is offered, and saving it says it failed")
    func unreachableHistoryFailsOnSave() throws {
        let editor = SessionEditorModel(session: try endedSession(), history: FlakyHistory(), now: clock.now)

        #expect(!editor.isReadOnly)
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

    private func endedSession() throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        return session
    }
}
