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
        return Dictionary(grouping: records, by: \.id).values.compactMap(Self.shown)
            .map {
                Tag(id: $0.id, kind: Tag.Kind(rawValue: $0.kind) ?? .piece, name: $0.name, isArchived: $0.isArchived)
            }
    }

    public func add(name: String, kind: Tag.Kind) throws -> Tag {
        let context = ModelContext(try store.container())
        let now = clock.now
        let record = TagRecord()
        record.id = UUID().uuidString.lowercased()
        record.kind = kind.rawValue
        record.name = name
        record.createdAt = now
        record.modifiedAt = now
        record.version = Self.version  // mutate:ignore - equals the schema default until a release raises it
        context.insert(record)
        try context.save()
        return Tag(id: record.id, kind: kind, name: name, isArchived: false)
    }

    public func rename(id: Tag.ID, to name: String) throws {
        try change(id) { $0.name = name }
    }

    public func setArchived(_ isArchived: Bool, id: Tag.ID) throws {
        try change(id) { $0.isArchived = isArchived }
    }

    /// Applies `apply` to the copy of `id` that ``tags()`` shows, unless a newer version wrote it,
    /// and keeps that copy the latest, so the other copies' older values never show again.
    private func change(_ id: Tag.ID, _ apply: (TagRecord) -> Void) throws {
        let context = ModelContext(try store.container())
        let copies = try context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { $0.id == id }))
        guard let shown = Self.shown(among: copies) else { return }
        guard shown.version <= Self.version else { throw RecordFromNewerVersion() }
        apply(shown)
        shown.version = Self.version  // mutate:ignore - equals the schema default until a release raises it
        // Never earlier than before: a copy from a device whose clock runs ahead must not overtake it.
        shown.modifiedAt = max(clock.now, shown.modifiedAt)
        try context.save()
    }

    /// The copy of an ID that shows: its latest change.
    private static func shown(among copies: [TagRecord]) -> TagRecord? {
        copies.max { $0.modifiedAt < $1.modifiedAt }  // mutate:ignore - only ties differ
    }
}
