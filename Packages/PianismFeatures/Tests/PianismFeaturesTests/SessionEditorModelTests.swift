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
        let editor = SessionEditorModel(session: session, history: history)
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

        #expect(SessionEditorModel(session: newer, history: history).isReadOnly)
        #expect(!SessionEditorModel(session: mine, history: history).isReadOnly)
    }

    @Test("SES-5: when history can't be reached, the edit is offered, and saving it says it failed")
    func unreachableHistoryFailsOnSave() throws {
        let editor = SessionEditorModel(session: try endedSession(), history: FlakyHistory())

        #expect(!editor.isReadOnly)
        #expect(!editor.save())
        #expect(editor.isShowingError)
    }

    private func endedSession() throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now)
        try session.stop(at: clock.now + 600)
        return session
    }
}
