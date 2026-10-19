import Foundation
import PianismCore
import Synchronization

// Not limited to Debug builds: `#Preview` bodies compile in Release too. Unused, this is stripped.

/// 2027-01-01 00:00 UTC, the moment the Practice previews are set at.
private let previewNow = Date(timeIntervalSince1970: 1_798_761_600)

extension PracticeModel {
    enum PreviewState {
        case ready, running, paused, pastNudge, capped
    }

    /// A model over an in-memory store, 25 minutes into a session, 95 minutes into one past the 90-minute nudge,
    /// or 5 hours into one that ends itself at the 4-hour cap, for previews.
    static func preview(_ state: PreviewState) -> PracticeModel {
        let minutesEarlier: TimeInterval =
            switch state {
            case .pastNudge: 70
            case .capped: 5 * 60 - 25
            default: 0
            }
        let started = previewNow.addingTimeInterval(-minutesEarlier * 60)
        let store = PreviewStore(state == .ready ? nil : PracticeSession(startedAt: started))
        let clock = PreviewClock(now: previewNow.addingTimeInterval(25 * 60 + 3))
        let model = PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock,
            nudge: 90 * 60, cap: 4 * 60 * 60)
        if state == .paused {
            model.pause()
        }
        return model
    }
}

/// Pieces and skills for previews, one archived.
private let previewTags = [
    Tag(id: "ballade", kind: .piece, name: "Ballade No. 1 in G minor", isArchived: false),
    Tag(id: "invention", kind: .piece, name: "Invention No. 1 in C major", isArchived: false),
    Tag(id: "nocturne", kind: .piece, name: "Nocturne in E-flat major", isArchived: true),
    Tag(id: "pedalling", kind: .skill, name: "Pedalling", isArchived: false),
]

extension TagPickerModel {
    /// A picker for `practice`'s session, which it tags with a piece and a built-in skill if running.
    static func preview(for practice: PracticeModel) -> TagPickerModel {
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary(previewTags))
        if practice.session?.state == .running {
            practice.setTags(["ballade", BuiltInSkill.scales.rawValue])
        }
        return model
    }

    /// A picker for a running, tagged session, with `query` typed.
    static func preview(query: String = "") -> TagPickerModel {
        let model = preview(for: .preview(.running))
        model.query = query
        return model
    }
}

extension HistoryModel {
    /// A model with practice today, yesterday and last week, or with none, for previews. Times are
    /// local, so "Today" holds in any time zone. `waiting` puts the sessions in the outbox and makes
    /// history fail to load, as during an outage (ADR 0007). `deleting` deletes the newest session, so Undo shows.
    static func preview(empty: Bool = false, waiting: Bool = false, deleting: Bool = false) -> HistoryModel {
        let sessions = InMemorySessionHistory()
        let midnight = Calendar.autoupdatingCurrent.startOfDay(for: previewNow)
        let hour: TimeInterval = 60 * 60
        // (Hours after this midnight, minutes of practice.)
        let practice = empty ? [] : [(18, 25), (8, 40), (-5, 15), (-150, 55)]
        for (hours, minutes) in practice {
            let start = midnight.addingTimeInterval(Double(hours) * hour)
            var session = PracticeSession(startedAt: start)
            // Every other session tagged, so both kinds of row show.
            try? session.setTags(hours.isMultiple(of: 2) ? ["ballade", BuiltInSkill.scales.rawValue] : [])
            try? session.stop(at: start.addingTimeInterval(Double(minutes) * 60))
            sessions.save(session)
        }
        let history: any SessionHistory = waiting ? PreviewUnavailableHistory() : sessions
        let outbox = waiting ? sessions : InMemorySessionHistory()
        let model = HistoryModel(
            history: history, tags: InMemoryTagLibrary(previewTags), outbox: outbox,
            clock: PreviewClock(now: midnight.addingTimeInterval(20 * hour)))
        if deleting {
            model.refresh()
            if let newest = model.days.first?.sessions.first { model.delete(newest) }
        }
        return model
    }
}

extension SessionEdit {
    /// A finished session, tagged with a piece and a built-in skill, to edit; read-only as if a newer
    /// version wrote it, if `readOnly`; overlapping another session, if `overlapping`.
    @MainActor
    static func preview(readOnly: Bool = false, overlapping: Bool = false) -> SessionEdit {
        var session = PracticeSession(startedAt: previewNow)
        try? session.stop(at: previewNow.addingTimeInterval(25 * 60 + 3))
        try? session.editTags(["ballade", BuiltInSkill.scales.rawValue])
        try? session.editNote("Coda hands separately, slowly. Left hand still rushes the run.")
        let history = InMemorySessionHistory(readOnlyIDs: readOnly ? [session.id] : [])
        history.save(session)
        var other = PracticeSession(startedAt: previewNow.addingTimeInterval(-10 * 60))
        try? other.stop(at: previewNow.addingTimeInterval(5 * 60))
        return SessionEdit(
            session: session, others: overlapping ? [other] : [], history: history,
            library: InMemoryTagLibrary(previewTags), now: previewNow.addingTimeInterval(60 * 60))
    }
}

private struct PreviewUnavailableHistory: SessionHistory {
    struct Unavailable: Error {}

    func sessions() throws -> [PracticeSession] { throw Unavailable() }
    func save(_: PracticeSession) throws { throw Unavailable() }
    func canEdit(id _: UUID) throws -> Bool { throw Unavailable() }
    func edit(_: PracticeSession) throws { throw Unavailable() }
    func delete(id _: UUID) throws { throw Unavailable() }
}

private struct PreviewClock: WallClock {
    let now: Date
}

private final class PreviewStore: RunningSessionStore {
    private let stored: Mutex<PracticeSession?>

    init(_ session: PracticeSession?) {
        stored = Mutex(session)
    }

    func current() -> PracticeSession? {
        stored.withLock { $0 }
    }

    func update<Value: Sendable>(_ change: (inout PracticeSession?) throws -> Value) throws -> Value {
        try stored.withLock { stored in
            var session = stored
            let value = try change(&session)
            stored = session
            return value
        }
    }
}
