import Foundation
import Observation
import PianismCore
import os

/// State and commands for editing a finished session, or one being added after the fact (SES-5).
@MainActor
@Observable
final class SessionEditorModel: TagTarget {
    /// The session as edited so far. History changes only when it's saved.
    private(set) var session: PracticeSession
    /// Whether the session is being added, so saving adds it to history rather than changing it.
    let isNew: Bool
    /// Whether a newer version wrote the session, so this one can't change it (ADR 0006).
    let isReadOnly: Bool
    /// The latest the session can end: when it was opened, so it can't end in the future, or its own end
    /// if a clock that ran ahead put that later.
    let latestEnd: Date
    /// Whether to show that the edit couldn't be saved.
    var isShowingError = false

    /// The session as it was opened, so moving its start or end works from the original pauses.
    private let original: PracticeSession
    /// History's other sessions, to warn when this one overlaps them.
    private let others: [PracticeSession]
    private let history: any SessionHistory
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    init(
        session: PracticeSession, isNew: Bool = false, others: [PracticeSession] = [], history: any SessionHistory,
        now: Date
    ) {
        self.session = session
        self.isNew = isNew
        latestEnd = max(now, session.endedAt ?? now)
        original = session
        self.others = others
        self.history = history
        // If history can't say, the edit is offered, and saving reports what went wrong.
        isReadOnly = !isNew && (try? history.canEdit(id: session.id)) == false
    }

    /// Whether the session differs from how it opened, so closing without saving asks first.
    var hasChanges: Bool { session != original }

    /// Another session this one shares time with, if any, which the day's total would count twice.
    var overlapping: PracticeSession? {
        others.first { $0.id != session.id && $0.overlaps(session) }
    }

    var start: Date {
        get { session.startedAt }
        set { retime(start: newValue, end: end) }
    }

    var end: Date {
        get { session.endedAt ?? session.startedAt }
        set { retime(start: start, end: newValue) }
    }

    var note: String {
        get { session.note }
        // Can't fail: the session being edited has ended.
        set { try? session.editNote(newValue) }
    }

    var tagIDs: [Tag.ID] { session.tagIDs }

    func setTags(_ ids: [Tag.ID]) {
        // Can't fail: the session being edited has ended.
        try? session.editTags(ids)
    }

    /// Moves the start or end of the session as it was opened, so a pause one change drops comes back
    /// when a later change covers it again, as when scrolling a time past it and back.
    private func retime(start: Date, end: Date) {
        // Each other field the editor changes is carried forward here, or moving a time would undo it.
        var retimed = original
        // The pickers keep the end between the start and `latestEnd`; a change that isn't is ignored.
        guard end <= latestEnd, (try? retimed.editTimes(start: start, end: end)) != nil else { return }
        try? retimed.editTags(session.tagIDs)
        try? retimed.editNote(session.note)
        session = retimed
    }

    /// Saves the edit, and returns whether it was saved, so the editor closes only then.
    func save() -> Bool {
        do {
            if isNew {
                try history.save(session)
            } else {
                try history.edit(session)
            }
            return true
        } catch {
            logger.error("Couldn't save an edited session: \(error, privacy: .public)")
            isShowingError = true
            return false
        }
    }
}

/// A finished session being edited or added, with the picker for its tags.
struct SessionEdit: Identifiable {
    let id: UUID
    let editor: SessionEditorModel
    let tags: TagPickerModel

    /// Edits `session`, saved in `history` or added to it if `isNew`, beside history's `others`, with tags
    /// from `library`, at `now`.
    @MainActor
    init(
        session: PracticeSession, isNew: Bool = false, others: [PracticeSession], history: any SessionHistory,
        library: any TagLibrary, now: Date
    ) {
        id = session.id
        editor = SessionEditorModel(session: session, isNew: isNew, others: others, history: history, now: now)
        tags = TagPickerModel(target: editor, library: library)
    }
}
