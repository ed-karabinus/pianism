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
    public let name: String
    /// Archived tags aren't offered for tagging, but sessions keep them. Tags are never deleted.
    // periphery:ignore - the tag picker hides archived tags (TAG-2, the next PR)
    public let isArchived: Bool

    public init(id: String, kind: Kind, name: String, isArchived: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isArchived = isArchived
    }

    /// The tag of `kind` among `tags` whose name is `name`, ignoring case, accents and surrounding
    /// spaces, archived ones included: adding a name already in use offers that tag instead (TAG-1).
    // periphery:ignore - the tag picker calls it (TAG-2, the next PR)
    public static func existing(named name: String, kind: Kind, in tags: [Tag]) -> Tag? {
        let wanted = comparable(name)
        return tags.first { $0.kind == kind && comparable($0.name) == wanted }
    }

    private static func comparable(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// The built-in skills: constants, never stored, so sync can never duplicate them (TAG-1, ADR 0004).
/// The app names them in the user's language. Sessions store these IDs, so they never change.
// periphery:ignore - the tag picker offers them (TAG-2, the next PR)
public enum BuiltInSkill: String, CaseIterable, Sendable {
    case scales = "skill.scales"
    case arpeggios = "skill.arpeggios"
    case technique = "skill.technique"
    case sightReading = "skill.sight-reading"
    case repertoire = "skill.repertoire"
    case improvisation = "skill.improvisation"
}
