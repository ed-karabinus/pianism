import Foundation
import Observation
import PianismCore
import os

/// What the tag picker tags: the running session (TAG-2), or a finished one being edited (SES-5).
@MainActor
protocol TagTarget: AnyObject {
    var tagIDs: [Tag.ID] { get }
    func setTags(_ ids: [Tag.ID])
}

/// State and commands for the tag picker, which tags a session and adds, renames, archives and merges tags, and adds
/// them inside others or moves them (TAG-1, TAG-2, TAG-4, TAG-5).
@MainActor
@Observable
public final class TagPickerModel {
    /// Every tag, built-in skills first, archived ones included.
    private var tags: [Tag] = []
    /// What the user typed, to find a tag or to name a new one.
    var query = ""
    /// Whether to show that the tags couldn't be loaded or changed.
    var isShowingError = false
    /// The parents shown unfolded: those with a chosen child when the picker opens, then as the user folds them (D3).
    private var unfolded: Set<Tag.ID> = []

    private var index = TagIndex([])
    /// The tags with anything inside them, archived or not, worked out once per load as each row asks (D2).
    private var parents: Set<Tag.ID> = []
    private let target: any TagTarget
    private let library: any TagLibrary
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "tags")

    /// Tags `practice`'s running session with tags kept in `library`.
    public convenience init(practice: PracticeModel, library: any TagLibrary) {
        self.init(target: practice, library: library)
    }

    /// Tags `target` with tags kept in `library`.
    init(target: any TagTarget, library: any TagLibrary) {
        self.target = target
        self.library = library
        refresh()
    }

    /// The session's tags, each merged tag as the tag it was merged into (ADR 0004).
    var selected: [Tag] {
        index.tags(for: target.tagIDs)
    }

    /// How the session's tags read, a child as "Parent › child" (D5).
    var selectedNames: [String] {
        index.names(for: target.tagIDs)
    }

    /// Clears a search left typed, as the model outlives the sheet, loads the tags, and unfolds each parent with a
    /// chosen child, so the choice shows (D3). Call when the picker opens.
    func open() {
        query = ""
        refresh()
        unfolded = Set(selected.compactMap { index.parent(of: $0)?.id })
    }

    /// Whether `parent`'s children show under it (D3).
    subscript(isUnfolded parent: Tag.ID) -> Bool {
        get { unfolded.contains(parent) }
        set { if newValue { unfolded.insert(parent) } else { unfolded.remove(parent) } }
    }

    /// The tags of `kind` to offer: top-level ones that are unarchived, the session's own or hold one of its tags or,
    /// while searching, every tag whose name contains the query, children and archived ones too, so they can come
    /// back (TAG-1, D3). Unarchived tags come first, each group by how ``label(_:)`` reads. A merged tag's name offers
    /// the tag it was merged into.
    func shown(_ kind: Tag.Kind) -> [Tag] {
        let search = Self.trimmed(query)
        let named = Tag.existing(named: search, kind: kind, in: tags).flatMap { index[$0.id] }
        let selectedIDs = Set(selected.map(\.id) + selected.compactMap { index.parent(of: $0)?.id })
        return sorted(
            tags.filter { tag in
                guard tag.kind == kind else { return false }
                if tag.id == named?.id { return true }
                if !search.isEmpty { return tag.mergedInto == nil && tag.name.localizedStandardContains(search) }
                return index.parent(of: tag) == nil && (!tag.isArchived || selectedIDs.contains(tag.id))
            })
    }

    /// The children to show folded under `parent`: unarchived ones and the session's own. None while searching, which
    /// lists every hit on its own (D3).
    func shown(inside parent: Tag) -> [Tag] {
        guard Self.trimmed(query).isEmpty else { return [] }
        let selectedIDs = Set(selected.map(\.id))
        return sorted(index.children(of: parent).filter { !$0.isArchived || selectedIDs.contains($0.id) })
    }

    /// How `tag` reads in the picker: its name under its parent, or "Parent › child" in a search, which lists it
    /// apart from its parent (D3).
    func label(_ tag: Tag) -> String {
        Self.trimmed(query).isEmpty ? tag.name : index.name(of: tag)
    }

    private func sorted(_ tags: [Tag]) -> [Tag] {
        tags.sorted {
            $0.isArchived != $1.isArchived
                ? !$0.isArchived : label($0).localizedStandardCompare(label($1)) == .orderedAscending
        }
    }

    /// The query as a new top-level tag of `kind`, or `nil` if it's empty or a top-level tag of that kind has the
    /// name (Q1).
    func newName(_ kind: Tag.Kind) -> String? {
        let name = Self.trimmed(query)
        guard !name.isEmpty, existing(named: name, kind: kind, inside: nil, among: tags) == nil else { return nil }
        return name
    }

    /// The tag of `kind` named `name` in the list inside `parent`, or at the top level for `nil`: names are unique
    /// within a list, so "Scales › D minor" and "Arpeggios › D minor" can both be (Q1). Lists are read through the
    /// index, as a stored link alone can't be trusted (ADR 0013); a merged tag is in the list of the tag it stands for.
    private func existing(named name: String, kind: Tag.Kind, inside parent: Tag.ID?, among tags: [Tag]) -> Tag? {
        let list = tags.filter { tag in index[tag.id].flatMap(index.parent(of:))?.id == parent }
        return Tag.existing(named: name, kind: kind, in: list)
    }

    /// Adds `tag` to the session, or removes it with any tag merged into it. Choosing an archived tag
    /// brings it back.
    func toggle(_ tag: Tag) {
        guard canPick(tag) else { return }
        let ids = target.tagIDs
        if selected.contains(where: { $0.id == tag.id }) {
            target.setTags(ids.filter { index[$0]?.id != tag.id })
            return
        }
        if tag.isArchived {
            perform { try library.setArchived(false, id: tag.id) }
        }
        target.setTags(ids + [tag.id])
    }

    /// Whether `tag` can be chosen: not one a newer version archived, which this one can't bring back, as its record is
    /// read-only (ADR 0006, #132). One already on the session can still be taken off.
    func canPick(_ tag: Tag) -> Bool {
        !(tag.isArchived && tag.isReadOnly) || selected.contains { $0.id == tag.id }
    }

    /// Adds the query as a new tag of `kind`, and tags the session with it.
    func add(_ kind: Tag.Kind) {
        guard let name = newName(kind) else { return }
        perform {
            let tag = try library.add(name: name, kind: kind)
            query = ""
            target.setTags(target.tagIDs + [tag.id])
        }
    }

    /// Whether a tag can be added inside `parent`: only at the top level and on offer, built-in skills included, so
    /// tags nest one level deep (ADR 0013). A tag that reads top-level but still has a stored link, as its parent
    /// hasn't synced yet or it lost a mutual nesting, can't either: a child added there becomes a grandchild once the
    /// link reads again, and only sync may make a record that breaks the rule.
    func canAddInside(_ parent: Tag) -> Bool {
        !parent.isArchived && parent.parentID == nil && index.parent(of: parent) == nil
    }

    /// Whether `name` can be added inside `parent`: it isn't empty, the name of a tag already inside it (Q1), or the
    /// parent's own name, as "Scales › Scales" reads like a mistake (the owner's pick 2026-11-10).
    func canAdd(_ name: String, inside parent: Tag) -> Bool {
        let name = Self.trimmed(name)
        return canAddInside(parent) && !name.isEmpty
            && existing(named: name, kind: parent.kind, inside: parent.id, among: tags) == nil
            && Tag.existing(named: name, kind: parent.kind, in: [parent]) == nil
    }

    /// Adds `name` inside `parent`, tags the session with it, as adding at the top level does, and unfolds the parent
    /// to show it (D3, D4). Clears a search, which would otherwise hide the new tag unless it matched.
    func add(_ name: String, inside parent: Tag) {
        guard canAdd(name, inside: parent) else { return }
        perform {
            let tag = try library.add(name: Self.trimmed(name), kind: parent.kind, inside: parent.id)
            query = ""
            target.setTags(target.tagIDs + [tag.id])
            unfolded.insert(parent.id)
        }
    }

    /// Whether `tag` can be renamed to `name`: it isn't empty, another tag's name in its list (Q1), or the name of its
    /// parent or of a tag inside it, so a child never shares its parent's name (the owner's pick 2026-11-10). A tag
    /// merged away doesn't count, so the tag it was merged into can take its name.
    func canRename(_ tag: Tag, to name: String) -> Bool {
        let name = Self.trimmed(name)
        let others = tags.filter { $0.id != tag.id && $0.mergedInto == nil }
        let parent = index.parent(of: tag)
        let family = (parent.map { [$0] } ?? []) + index.children(of: tag)
        return !name.isEmpty && existing(named: name, kind: tag.kind, inside: parent?.id, among: others) == nil
            && Tag.existing(named: name, kind: tag.kind, in: family) == nil
    }

    func rename(_ tag: Tag, to name: String) {
        guard canRename(tag, to: name) else { return }
        perform { try library.rename(id: tag.id, to: Self.trimmed(name)) }
    }

    /// The target tempos a piece can be given, in beats per minute (TAG-3): every real one, but not typos.
    static let targetTempos = 20...300

    /// Whether `tag` can be given a composer and a target tempo: a piece the user added (TAG-3).
    func canHaveDetails(_ tag: Tag) -> Bool {
        tag.kind == .piece && !tag.isReadOnly
    }

    /// Whether `tempo` can be a target tempo: empty for none, or a whole number in ``targetTempos``.
    func canSetDetails(tempo: String) -> Bool {
        let tempo = Self.trimmed(tempo)
        return tempo.isEmpty || Int(tempo).map(Self.targetTempos.contains) == true
    }

    /// Saves only what changed from `tag`, as opened, since a save makes this the latest copy: a change synced from
    /// another device since then, to the other detail, stays (SYN-1).
    func setDetails(_ tag: Tag, composer: String, tempo: String) {
        guard canSetDetails(tempo: tempo) else { return }
        let composer = Self.trimmed(composer)
        let targetTempo = Int(Self.trimmed(tempo))
        guard composer != tag.composer || targetTempo != tag.targetTempo else { return }
        perform {
            let latest = try library.tags().first { $0.id == tag.id } ?? tag
            try library.setDetails(
                composer: composer != tag.composer ? composer : latest.composer,
                targetTempo: targetTempo != tag.targetTempo ? targetTempo : latest.targetTempo, id: tag.id)
        }
    }

    /// How many unarchived tags are inside `tag`, which can't be archived until they are (D1): an archived tag never
    /// has anything live inside it. Archived children don't count.
    func liveChildren(of tag: Tag) -> Int {
        index.children(of: tag).count { !$0.isArchived }
    }

    /// Stops offering `tag`, unless something live is inside it (D1). Sessions keep it (TAG-1).
    func archive(_ tag: Tag) {
        guard liveChildren(of: tag) == 0 else { return }
        perform { try library.setArchived(true, id: tag.id) }
    }

    /// The tags `tag` can be merged into: the others of its kind in its list, inside the same parent or at the top
    /// level, that are on offer and have nothing inside them, built-in skills too (TAG-4, D2). Merging a parent, or
    /// across parents, would leave children counting toward a parent they don't read inside.
    func mergeTargets(for tag: Tag) -> [Tag] {
        let parent = index.parent(of: tag)?.id
        return tags.filter {
            $0.kind == tag.kind && $0.id != tag.id && !$0.isArchived && index.parent(of: $0)?.id == parent
                && !parents.contains($0.id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether `tag` can be merged into another. Built-in skills have no record to change. Archived tags can't, so
    /// that undoing, which unarchives (ADR 0006), restores a merged tag exactly. Nor can a tag with anything inside it,
    /// archived or not (D2).
    func canMerge(_ tag: Tag) -> Bool {
        !tag.isReadOnly && !tag.isArchived && !parents.contains(tag.id) && !mergeTargets(for: tag).isEmpty
    }

    func merge(_ tag: Tag, into kept: Tag) {
        perform { try library.merge(id: tag.id, into: kept.id) }
    }

    /// The tags merged away, by name, each with the tag it stands for, so a merge can be undone at any time. None
    /// while searching, which finds tags to use.
    var merged: [(tag: Tag, kept: Tag)] {
        guard Self.trimmed(query).isEmpty else { return [] }
        return tags.compactMap { tag in
            guard let kept = index[tag.id], kept.id != tag.id else { return nil }
            return (tag, kept)
        }
        .sorted { $0.tag.name.localizedStandardCompare($1.tag.name) == .orderedAscending }
    }

    func undoMerge(_ tag: Tag) {
        perform { try library.unmerge(id: tag.id) }
    }

    /// The tag `tag` reads inside, or `nil` at the top level (ADR 0013).
    func parent(of tag: Tag) -> Tag? {
        index.parent(of: tag)
    }

    /// The tags `tag` can be moved inside: the others of its kind at the top level, on offer and not merged away,
    /// built-in skills too, its current parent included (D4). A child isn't one, so tags nest one level deep.
    func moveTargets(for tag: Tag) -> [Tag] {
        tags.filter {
            // A tag can read top-level while it still stores a parent: a grandchild, the loser of a ring, the winner of
            // a mutual nesting, or one whose parent hasn't synced yet. A tag moved inside it would read top-level, now
            // or once that parent arrives, so it isn't offered, as Add Inside refuses it too. Two exceptions: its link
            // names the tag being moved, which the move clears, or it's where the tag already is, shown but never
            // written.
            $0.kind == tag.kind && $0.id != tag.id && !$0.isArchived && $0.mergedInto == nil
                && index.parent(of: $0) == nil
                && ($0.parentID == nil || index.link($0)?.id == tag.id || $0.id == index.parent(of: tag)?.id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether `tag` can be moved: a user's own tag, as built-in skills are never children, with nothing inside it,
    /// archived or not, which it would take to a second level, and somewhere to go (D4, ADR 0013).
    func canMove(_ tag: Tag) -> Bool {
        !tag.isReadOnly && !parents.contains(tag.id) && (index.parent(of: tag) != nil || !moveTargets(for: tag).isEmpty)
    }

    /// Why `tag` can't go inside `parent`, or to the top level for `nil`: `parent` or another tag in that list has its
    /// name, as names are unique within a list (Q1). `nil` if it can. A tag merged away doesn't count, as for Rename.
    func moveRefusal(_ tag: Tag, to parent: Tag?) -> String? {
        // A child can't share its parent's name, as Add Inside and Rename refuse too (the owner's pick 2026-11-10).
        if let parent, Tag.existing(named: tag.name, kind: tag.kind, in: [parent]) != nil {
            return tag.kind == .piece
                ? String(
                    localized: "A piece can't sit inside one with the same name. Rename one first.", bundle: .module,
                    comment: "Why a piece or skill can't be moved")
                : String(
                    localized: "A skill can't sit inside one with the same name. Rename one first.", bundle: .module,
                    comment: "Why a piece or skill can't be moved")
        }
        let others = tags.filter { $0.id != tag.id && $0.mergedInto == nil }
        guard existing(named: tag.name, kind: tag.kind, inside: parent?.id, among: others) != nil else { return nil }
        let name = tag.name
        return switch (tag.kind, parent?.name) {
        case (.piece, nil):
            String(
                localized: "A piece named “\(name)” is already at the top level. Rename one first.", bundle: .module,
                comment: "Why a piece or skill can't be moved")
        case (.skill, nil):
            String(
                localized: "A skill named “\(name)” is already at the top level. Rename one first.", bundle: .module,
                comment: "Why a piece or skill can't be moved")
        case (.piece, let parent?):
            String(
                localized: "A piece named “\(name)” is already inside “\(parent)”. Rename one first.", bundle: .module,
                comment: "Why a piece or skill can't be moved")
        case (.skill, let parent?):
            String(
                localized: "A skill named “\(name)” is already inside “\(parent)”. Rename one first.", bundle: .module,
                comment: "Why a piece or skill can't be moved")
        }
    }

    /// Moves `tag` inside `parent`, or to the top level for `nil`, unless it's there already, `parent` isn't one of
    /// ``moveTargets(for:)`` or the move is refused (D4). Unfolds the new parent to show it there, as Add Inside does.
    /// Its sessions aren't written: they follow it, as they name the tag, not its place.
    func move(_ tag: Tag, to parent: Tag?) {
        let from = index.parent(of: tag)
        guard canMove(tag), parent?.id != from?.id, moveRefusal(tag, to: parent) == nil else { return }
        if let parent, !moveTargets(for: tag).contains(where: { $0.id == parent.id }) { return }
        perform {
            // After two devices nest a pair opposite ways, the tag that won still names this one in its own link. Left
            // there, the parent it leaves would jump inside it, and the parent it joins could win the pair and land
            // inside it instead, so that link is cleared: two writes, no surprise (ADR 0013, plan §3). It goes first,
            // so if the move's own write then fails, nothing has moved, rather than the other tag jumping.
            for end in [from, parent].compactMap(\.self) where index.link(end)?.id == tag.id {
                try library.setParent(id: end.id, to: nil)
            }
            try library.setParent(id: tag.id, to: parent?.id)
            if let parent { unfolded.insert(parent.id) }
        }
    }

    /// Loads the tags again. Call when the picker opens, and when iCloud brings changes (SYN-1).
    public func refresh() {
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
            let all = try library.allTags()
            index = TagIndex(all)
            // As the index has them, so the tag that opposite merges settled on is offered (TAG-4).
            tags = all.map { tag in
                guard let kept = index[tag.id], kept.id == tag.id else { return tag }
                return kept
            }
            parents = Set(all.compactMap { index[$0.id].flatMap(index.parent(of:))?.id })
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

extension Tag {
    /// A piece's composer and target tempo as a line, such as "Chopin, 72 BPM", or `nil` if it has neither
    /// (TAG-3).
    var details: String? {
        let tempo = targetTempo.map { String(localized: "\($0) BPM", bundle: .module, comment: "A target tempo") }
        let details = [composer.isEmpty ? nil : composer, tempo].compactMap(\.self)
        return details.isEmpty ? nil : details.formatted(.list(type: .and, width: .narrow))
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
