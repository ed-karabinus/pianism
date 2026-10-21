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

    /// Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    func rename(id: Tag.ID, to name: String) throws

    /// Archives or unarchives a tag. Throws ``RecordFromNewerVersion`` for a tag a newer version wrote.
    func setArchived(_ isArchived: Bool, id: Tag.ID) throws

    /// Sets a piece's composer and target tempo (TAG-3). Throws ``RecordFromNewerVersion`` for a tag a newer
    /// version wrote.
    func setDetails(composer: String, targetTempo: Int?, id: Tag.ID) throws
}
