import Foundation
import Observation
import PianismCore
import os

/// State and commands for editing a finished session (SES-5).
@MainActor
@Observable
final class SessionEditorModel: TagTarget {
    /// The session as edited so far. History changes only when it's saved.
    private(set) var session: PracticeSession
    /// Whether a newer version wrote the session, so this one can't change it (ADR 0006).
    let isReadOnly: Bool
    /// Whether to show that the edit couldn't be saved.
    var isShowingError = false

    private let history: any SessionHistory
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    init(session: PracticeSession, history: any SessionHistory) {
        self.session = session
        self.history = history
        // If history can't say, the edit is offered, and saving reports what went wrong.
        isReadOnly = (try? history.canEdit(id: session.id)) == false
    }

    var tagIDs: [Tag.ID] { session.tagIDs }

    func setTags(_ ids: [Tag.ID]) {
        // Can't fail: the session being edited has ended.
        try? session.editTags(ids)
    }

    /// Saves the edit, and returns whether it was saved, so the editor closes only then.
    func save() -> Bool {
        do {
            try history.edit(session)
            return true
        } catch {
            logger.error("Couldn't save an edited session: \(error, privacy: .public)")
            isShowingError = true
            return false
        }
    }
}

/// A finished session being edited, with the picker for its tags.
struct SessionEdit: Identifiable {
    let id: UUID
    let editor: SessionEditorModel
    let tags: TagPickerModel

    /// Edits `session`, saved in `history`, with tags from `library`.
    @MainActor
    init(session: PracticeSession, history: any SessionHistory, library: any TagLibrary) {
        id = session.id
        editor = SessionEditorModel(session: session, history: history)
        tags = TagPickerModel(target: editor, library: library)
    }
}
