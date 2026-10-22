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

    /// Another session this one shares at least a minute of practice with, if any, and how much, which the
    /// day's total counts twice. Less is ignored: the time pickers can't show it, so it can't be fixed.
    var overlap: (session: PracticeSession, shared: TimeInterval)? {
        others.lazy.filter { $0.id != self.session.id }
            .map { ($0, $0.sharedPractice(with: self.session)) }
            .first { $0.shared >= 60 }
    }

    var start: Date {
        get { session.startedAt }
        set { retime(start: picked(newValue, opened: original.startedAt, otherEnd: end, within: startRange), end: end) }
    }

    var end: Date {
        get { session.endedAt ?? session.startedAt }
        set {
            let opened = original.endedAt ?? original.startedAt
            retime(start: start, end: picked(newValue, opened: opened, otherEnd: start, within: endRange))
        }
    }

    /// The times the start and end wheels offer.
    var startRange: ClosedRange<Date> { .distantPast...end }
    var endRange: ClosedRange<Date> { start...latestEnd }

    /// A time picked on the wheels. Back in the minute it opened in, it's the time it opened at, so scrolling away
    /// and back changes nothing; anywhere else it takes the other end's seconds.
    private func picked(_ date: Date, opened: Date, otherEnd: Date, within range: ClosedRange<Date>) -> Date {
        Calendar.autoupdatingCurrent.isDate(date, equalTo: opened, toGranularity: .minute)
            ? opened : date.keepingSeconds(of: otherEnd, within: range)
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
    ///
    /// Saves only what changed, as a save makes this the latest copy: a change synced from another device since
    /// the editor opened, to anything not edited here, stays (SYN-1).
    func save() -> Bool {
        guard isNew || hasChanges else { return true }
        do {
            if isNew {
                try history.save(session)
            } else {
                let stored = try history.sessions().first { $0.id == session.id } ?? session
                try history.edit(edited(stored))
            }
            return true
        } catch {
            logger.error("Couldn't save an edited session: \(error, privacy: .public)")
            isShowingError = true
            return false
        }
    }

    /// `latest`, the stored copy, with this edit's changes: the times as one, the tags and the note.
    private func edited(_ latest: PracticeSession) throws -> PracticeSession {
        var latest = latest
        if session.startedAt != original.startedAt || session.endedAt != original.endedAt {
            try latest.editTimes(start: start, end: end)
        }
        if session.tagIDs != original.tagIDs {
            try latest.editTags(session.tagIDs)
        }
        if session.note != original.note {
            try latest.editNote(session.note)
        }
        return latest
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
