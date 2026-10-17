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
    /// The tag this one was merged into, which its sessions count toward (ADR 0004). Merging arrives
    /// with TAG-4, but a newer version on another device may already have merged.
    public let mergedInto: Tag.ID?
    /// Decides which tag survives when two devices merged a pair in opposite directions (ADR 0004).
    public let createdAt: Date
    /// Built-in skills, and tags a newer version wrote (ADR 0006), can't be renamed or archived.
    public let isReadOnly: Bool

    public init(
        id: String, kind: Kind, name: String, isArchived: Bool, mergedInto: Tag.ID? = nil,
        createdAt: Date = .distantPast, isReadOnly: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isArchived = isArchived
        self.mergedInto = mergedInto
        self.createdAt = createdAt
        self.isReadOnly = isReadOnly
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

/// Tags by ID, with each merged tag standing for the tag it was merged into (ADR 0004).
public struct TagIndex: Sendable {
    private let resolved: [Tag.ID: Tag]

    /// Follows each tag's merges to the end. Two devices merging a pair in opposite directions make a
    /// cycle; every tag in it then stands for the one created first, ties broken by ID, so all devices
    /// agree. A tag merged into one that hasn't synced yet stands for itself until it arrives.
    public init(_ tags: [Tag]) {
        let byID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        resolved = byID.mapValues { tag in
            var chain = [tag]
            var current = tag
            while let next = current.mergedInto.flatMap({ byID[$0] }) {
                if let loop = chain.firstIndex(where: { $0.id == next.id }) {
                    return chain[loop...].reduce(next) {
                        ($1.createdAt, $1.id) < ($0.createdAt, $0.id) ? $1 : $0  // mutate:ignore - IDs never tie
                    }
                }
                chain.append(next)
                current = next
            }
            return current
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
}
