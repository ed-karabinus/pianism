/// Thrown when a record was written by a newer version of the app, which this one could damage by
/// changing it (ADR 0006). The user needs to update to change it.
public struct RecordFromNewerVersion: Error {
    public init() {}
}

/// The user's own pieces and skills (TAG-1, ADR 0004). Built-in skills aren't stored.
public protocol TagLibrary: Sendable {
    /// Every tag the user added, archived ones included, each ID once.
    func tags() throws -> [Tag]

    /// Adds a new tag and returns it. Offer an ``Tag/existing(named:kind:in:)`` tag first.
    func add(name: String, kind: Tag.Kind) throws -> Tag

    /// Adds a new tag inside `parent` and returns it: one record, so one change to sync, not an add and then a
    /// move (TAG-5, ADR 0013). The caller checks the parent can take it; the library stores what it's given.
    func add(name: String, kind: Tag.Kind, inside parent: Tag.ID) throws -> Tag

    /// Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    func rename(id: Tag.ID, to name: String) throws

    /// Archives or unarchives a tag. Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    func setArchived(_ isArchived: Bool, id: Tag.ID) throws

    /// Sets a piece's composer and target tempo (TAG-3). Throws ``RecordFromNewerVersion`` for a tag a newer
    /// version wrote.
    func setDetails(composer: String, targetTempo: Int?, id: Tag.ID) throws

    /// Makes a tag stand for `kept`, and archives it. Its sessions aren't touched, and now count toward `kept`
    /// (TAG-4, ADR 0004). Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    func merge(id: Tag.ID, into kept: Tag.ID) throws

    /// Undoes ``merge(id:into:)``, which also unarchives the tag (ADR 0006). Throws ``RecordFromNewerVersion`` for
    /// a tag a newer version wrote.
    func unmerge(id: Tag.ID) throws

    /// Puts a tag inside `parent`, or at the top level for `nil`. Its sessions aren't touched, and count toward the
    /// parent too (TAG-5, ADR 0013). Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    // periphery:ignore - stored before any screen uses it, so the CloudKit deploy has the field (ADR 0013)
    func setParent(id: Tag.ID, to parent: Tag.ID?) throws
}
