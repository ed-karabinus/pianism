import Foundation
import PianismCore
import SwiftData

/// The user's pieces and skills, kept in the ``HistoryStore`` beside finished sessions (TAG-1, ADR 0004).
// periphery:ignore - the tag picker uses it (TAG-2, the next PR)
public final class SwiftDataTagLibrary: TagLibrary {
    /// The record version this app writes; it changes only records up to it (ADR 0006).
    static let version = 1

    private let store: HistoryStore
    private let clock: any WallClock

    /// A library kept in `store`. `clock` stamps when each tag was created and last changed.
    public init(store: HistoryStore, clock: any WallClock) {
        self.store = store
        self.clock = clock
    }

    /// Each ID once, as its latest change, in case sync delivers a duplicate (ADR 0004).
    public func tags() throws -> [Tag] {
        let records = try ModelContext(store.container()).fetch(FetchDescriptor<TagRecord>())
        return Dictionary(grouping: records, by: \.id).values.compactMap { duplicates in
            duplicates.max { $0.modifiedAt < $1.modifiedAt }  // mutate:ignore - only ties differ
        }
        .map { Tag(id: $0.id, kind: Tag.Kind(rawValue: $0.kind) ?? .piece, name: $0.name, isArchived: $0.isArchived) }
    }

    public func add(name: String, kind: Tag.Kind) throws -> Tag {
        let context = ModelContext(try store.container())
        let record = TagRecord()
        record.id = UUID().uuidString.lowercased()
        record.kind = kind.rawValue
        record.name = name
        record.createdAt = clock.now
        record.modifiedAt = clock.now
        context.insert(record)
        try context.save()
        return Tag(id: record.id, kind: kind, name: name)
    }

    public func rename(id: Tag.ID, to name: String) throws {
        try change(id) { $0.name = name }
    }

    public func setArchived(_ isArchived: Bool, id: Tag.ID) throws {
        try change(id) { $0.isArchived = isArchived }
    }

    /// Applies `apply` to every record with `id`, so a duplicate from sync can't bring back the old
    /// value, unless a newer version wrote any of them.
    private func change(_ id: Tag.ID, _ apply: (TagRecord) -> Void) throws {
        let context = ModelContext(try store.container())
        let records = try context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { $0.id == id }))
        guard records.allSatisfy({ $0.version <= Self.version }) else { throw RecordFromNewerVersion() }
        for record in records {
            apply(record)
            record.modifiedAt = clock.now
        }
        try context.save()
    }
}
