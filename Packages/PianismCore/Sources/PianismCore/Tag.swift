import Foundation

/// A piece or a skill that practice time is labelled with (TAG-1).
public struct Tag: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case piece
        case skill
    }

    /// A lowercase UUID for the user's own tags, or a ``BuiltInSkill`` ID (ADR 0004).
    public let id: String
    public let kind: Kind
    public internal(set) var name: String
    /// Archived tags aren't offered for tagging, but sessions keep them. Tags are never deleted.
    public internal(set) var isArchived: Bool
    /// The tag this one was merged into, which its sessions count toward (TAG-4, ADR 0004).
    public internal(set) var mergedInto: Tag.ID?
    /// The tag this one sits inside, as stored, or `nil` at the top level (TAG-5, ADR 0013). Sync can deliver a
    /// link no device would write, so it's never trusted without the rules of ADR 0013.
    public internal(set) var parentID: Tag.ID?
    /// Decides which tag survives when two devices merged a pair in opposite directions (ADR 0004).
    public let createdAt: Date
    /// Built-in skills, and tags a newer version wrote (ADR 0006), can't be renamed, archived or given
    /// details.
    public let isReadOnly: Bool
    /// A piece's composer; empty if none (TAG-3).
    public internal(set) var composer: String
    /// The tempo a piece is being worked up to, in beats per minute (TAG-3).
    public internal(set) var targetTempo: Int?

    public init(
        id: String, kind: Kind, name: String, isArchived: Bool, mergedInto: Tag.ID? = nil, parentID: Tag.ID? = nil,
        createdAt: Date = .distantPast, isReadOnly: Bool = false, composer: String = "", targetTempo: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isArchived = isArchived
        self.mergedInto = mergedInto
        self.parentID = parentID
        self.createdAt = createdAt
        self.isReadOnly = isReadOnly
        self.composer = composer
        self.targetTempo = targetTempo
    }

    /// The tag of `kind` among `tags` whose name is `name`, ignoring case, accents and surrounding
    /// spaces, archived ones included: adding a name already in use offers that tag instead (TAG-1).
    /// An unarchived tag wins over an archived one with the same name, such as one merged away.
    public static func existing(named name: String, kind: Kind, in tags: [Tag]) -> Tag? {
        let wanted = comparable(name)
        let matches = tags.filter { $0.kind == kind && comparable($0.name) == wanted }
        return matches.first { !$0.isArchived } ?? matches.first
    }

    private static func comparable(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// The built-in skills: constants, never stored, so sync can never duplicate them (TAG-1, ADR 0004).
/// The app names them in the user's language. Sessions store these IDs, so they never change.
public enum BuiltInSkill: String, CaseIterable, Sendable {
    case scales = "skill.scales"
    case arpeggios = "skill.arpeggios"
    case technique = "skill.technique"
    case sightReading = "skill.sight-reading"
    case repertoire = "skill.repertoire"
    case improvisation = "skill.improvisation"
}

/// Tags by ID, with each merged tag standing for the tag it was merged into (ADR 0004), and each tag inside at most
/// one other, whatever links sync delivered (ADR 0013).
public struct TagIndex: Sendable {
    private var resolved: [Tag.ID: Tag]

    /// Follows each tag's merges to the end. Two devices merging a pair in opposite directions make a
    /// cycle; every tag in it then stands for the one created first, ties broken by ID, so all devices
    /// agree, and that tag is no longer merged or archived. A tag merged into one that hasn't synced yet
    /// stands for itself until it arrives.
    public init(_ tags: [Tag]) {
        let byID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        resolved = byID.mapValues { tag in
            var chain = [tag]
            var current = tag
            while let next = current.mergedInto.flatMap({ byID[$0] }) {
                if let loop = chain.firstIndex(where: { $0.id == next.id }) {
                    var kept = chain[loop...].reduce(next) {
                        ($1.createdAt, $1.id) < ($0.createdAt, $0.id) ? $1 : $0  // mutate:ignore - IDs never tie
                    }
                    kept.mergedInto = nil
                    kept.isArchived = false
                    return kept
                }
                chain.append(next)
                current = next
            }
            return current
        }
        // One device archived a parent while another added a child inside it. It reads as unarchived, so an
        // archived tag never has anything live inside it (D1), as stored again once the child is archived too: a
        // read, not a write (ADR 0013). A merged tag's own link is never read: its key holds the kept tag, so it can't
        // keep a parent live by itself.
        let live = Set(resolved.values.filter { !$0.isArchived }.compactMap { parent(of: $0)?.id })
        for (id, tag) in resolved where live.contains(tag.id) {
            resolved[id]?.isArchived = false
        }
    }

    /// The tag `id` stands for, or `nil` if it isn't known, such as a tag that hasn't synced yet.
    public subscript(id: Tag.ID) -> Tag? {
        resolved[id]
    }

    /// The tags `ids` stand for, each once, in order, leaving out unknown IDs (TAG-2).
    public func tags(for ids: [Tag.ID]) -> [Tag] {
        var seen = Set<Tag.ID>()
        return ids.compactMap { resolved[$0] }.filter { seen.insert($0.id).inserted }
    }

    /// The tags a session tagged `ids` counts toward: its tags, then their parents, each once, so two children of
    /// one parent count once toward it (TAG-5).
    func counted(for ids: [Tag.ID]) -> [Tag] {
        let tags = tags(for: ids)
        var seen = Set<Tag.ID>()
        return (tags + tags.compactMap(parent(of:))).filter { seen.insert($0.id).inserted }
    }

    /// The tag that `tag`, one of this index's, sits inside, or `nil` at the top level (ADR 0013). It looks one link
    /// further and never asks for the parent's own parent: that recursion never ends on a ring three devices can make,
    /// T inside P, P inside G and G inside T, which this reads as three top-level tags.
    public func parent(of tag: Tag) -> Tag? {
        // A tag from outside the index, such as a merged one from the library, reads as the tag it stands for, never
        // through its own stale link.
        guard let tag = resolved[tag.id], let parent = link(tag) else { return nil }
        guard let grandparent = link(parent) else { return parent }
        // Each names the other: the one created first is the parent, ties broken by ID, as for opposite merges, so
        // every device agrees. Any other grandparent would make a second level, so `tag` shows at the top level until
        // its parent moves out, and its stored link puts it back inside then.
        guard grandparent.id == tag.id else { return nil }
        return (parent.createdAt, parent.id) < (tag.createdAt, tag.id) ? parent : nil  // mutate:ignore - IDs never tie
    }

    /// The tags that read inside `tag`, one of this index's, archived ones included, each once, in no set order
    /// (ADR 0013).
    public func children(of tag: Tag) -> [Tag] {
        var seen = Set<Tag.ID>()
        // A merged tag's ID stands for its kept tag too, so the kept tag can turn up more than once.
        return resolved.values.filter { parent(of: $0)?.id == tag.id && seen.insert($0.id).inserted }
    }

    /// How a tag of this index reads in a list of a session's tags: "Parent › child", or its own name at the top level
    /// (D5).
    public func name(of tag: Tag) -> String {
        parent(of: tag).map { "\($0.name) › \(tag.name)" } ?? tag.name
    }

    /// How a session tagged `ids` names its tags, each once, in order (D5): what History, Practice, the session
    /// editor and the CSV show.
    public func names(for ids: [Tag.ID]) -> [String] {
        tags(for: ids).map(name(of:))
    }

    /// The tag `tag`'s stored parent stands for, through merges, unless it's unknown here (not synced yet), `tag`
    /// itself (a parent merged into its own child) or of the other kind (ADR 0013). Like ``parent(of:)``, it reads
    /// `tag` as the tag its ID stands for here, so a tag from outside the index, such as a merged one from the
    /// library, is never read through its own stale link, and a tag the index doesn't know has none. Public for Move,
    /// which clears a link naming the tag it moves, so the other tag of a mutual nesting doesn't end up inside it.
    public func link(_ tag: Tag) -> Tag? {
        guard let tag = resolved[tag.id], let parent = tag.parentID.flatMap({ resolved[$0] }), parent.id != tag.id,
            parent.kind == tag.kind
        else { return nil }
        return parent
    }
}
