import Foundation
import Observation
import PianismCore
import os

/// State and commands for the tag picker, which tags the running session and adds, renames and
/// archives tags (TAG-1, TAG-2).
@MainActor
@Observable
public final class TagPickerModel {
    /// Every tag, built-in skills first, archived ones included.
    private(set) var tags: [Tag] = []
    /// What the user typed, to find a tag or to name a new one.
    var query = ""
    /// Whether to show that the tags couldn't be loaded or changed.
    var isShowingError = false

    private var index = TagIndex([])
    private let practice: PracticeModel
    private let library: any TagLibrary
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "tags")

    /// Tags `practice`'s session with tags kept in `library`.
    public init(practice: PracticeModel, library: any TagLibrary) {
        self.practice = practice
        self.library = library
        refresh()
    }

    /// The running session's tags, each merged tag as the tag it was merged into (ADR 0004).
    var selected: [Tag] {
        index.tags(for: practice.session?.tagIDs ?? [])
    }

    /// The tags of `kind` to offer, by name: unarchived ones and the session's own, narrowed to names
    /// containing the query, plus an archived tag the query names, so that it can come back (TAG-1).
    func shown(_ kind: Tag.Kind) -> [Tag] {
        let search = Self.trimmed(query)
        let named = Tag.existing(named: search, kind: kind, in: tags)
        let selectedIDs = Set(selected.map(\.id))
        return tags.filter { tag in
            guard tag.kind == kind else { return false }
            if tag.id == named?.id { return true }
            return (!tag.isArchived || selectedIDs.contains(tag.id))
                && (search.isEmpty || tag.name.localizedStandardContains(search))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The query as a new tag of `kind`, or `nil` if it's empty or a tag of that kind has the name.
    func newName(_ kind: Tag.Kind) -> String? {
        let name = Self.trimmed(query)
        guard !name.isEmpty, Tag.existing(named: name, kind: kind, in: tags) == nil else { return nil }
        return name
    }

    /// Adds `tag` to the session, or removes it with any tag merged into it. Choosing an archived tag
    /// brings it back.
    func toggle(_ tag: Tag) {
        let ids = practice.session?.tagIDs ?? []
        if selected.contains(where: { $0.id == tag.id }) {
            practice.setTags(ids.filter { index[$0]?.id != tag.id })
            return
        }
        if tag.isArchived {
            perform { try library.setArchived(false, id: tag.id) }
        }
        practice.setTags(ids + [tag.id])
    }

    /// Adds the query as a new tag of `kind`, and tags the session with it.
    func add(_ kind: Tag.Kind) {
        guard let name = newName(kind) else { return }
        perform {
            let tag = try library.add(name: name, kind: kind)
            query = ""
            practice.setTags((practice.session?.tagIDs ?? []) + [tag.id])
        }
    }

    /// Whether `tag` can be renamed to `name`: it isn't empty, or another tag's name of its kind.
    func canRename(_ tag: Tag, to name: String) -> Bool {
        let name = Self.trimmed(name)
        return !name.isEmpty && Tag.existing(named: name, kind: tag.kind, in: tags.filter { $0.id != tag.id }) == nil
    }

    func rename(_ tag: Tag, to name: String) {
        guard canRename(tag, to: name) else { return }
        perform { try library.rename(id: tag.id, to: Self.trimmed(name)) }
    }

    /// Stops offering `tag`. Sessions keep it (TAG-1).
    func archive(_ tag: Tag) {
        perform { try library.setArchived(true, id: tag.id) }
    }

    /// Loads the tags again. Call when the picker opens and when the app becomes active: another
    /// device, or a newer version of the app, may have changed them.
    func refresh() {
        perform {}
    }

    /// Runs `change`, then shows the tags as stored, even if it failed: a tag a newer version wrote
    /// then shows as read-only.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            logger.error("Couldn't change the tags: \(error, privacy: .public)")
            isShowingError = true
        }
        do {
            tags = try library.allTags()
            index = TagIndex(tags)
        } catch {
            logger.error("Couldn't load the tags: \(error, privacy: .public)")
            isShowingError = true
        }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TagLibrary {
    /// The built-in skills, named in the user's language, then the user's own tags (TAG-1).
    func allTags() throws -> [Tag] {
        BuiltInSkill.allCases.map(\.tag) + (try tags())
    }
}

extension BuiltInSkill {
    /// The skill as a tag, which can't be renamed or archived: there's no record to change.
    var tag: Tag {
        Tag(id: rawValue, kind: .skill, name: name, isArchived: false, isReadOnly: true)
    }

    private var name: String {
        switch self {
        case .scales: String(localized: "Scales", bundle: .module, comment: "A built-in skill")
        case .arpeggios: String(localized: "Arpeggios", bundle: .module, comment: "A built-in skill")
        case .technique: String(localized: "Technique", bundle: .module, comment: "A built-in skill")
        case .sightReading: String(localized: "Sight-reading", bundle: .module, comment: "A built-in skill")
        case .repertoire: String(localized: "Repertoire", bundle: .module, comment: "A built-in skill")
        case .improvisation: String(localized: "Improvisation", bundle: .module, comment: "A built-in skill")
        }
    }
}
