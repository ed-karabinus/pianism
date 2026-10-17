import Foundation
import Synchronization

/// A ``TagLibrary`` kept in memory, for previews and tests.
public final class InMemoryTagLibrary: TagLibrary {
    private let stored: Mutex<[Tag]>

    public init(_ tags: [Tag] = []) {
        stored = Mutex(tags)
    }

    public func tags() -> [Tag] {
        stored.withLock { $0 }
    }

    public func add(name: String, kind: Tag.Kind) -> Tag {
        let tag = Tag(id: UUID().uuidString.lowercased(), kind: kind, name: name, isArchived: false)
        stored.withLock { $0.append(tag) }
        return tag
    }

    public func rename(id: Tag.ID, to name: String) throws {
        try change(id) { $0.name = name }
    }

    public func setArchived(_ isArchived: Bool, id: Tag.ID) throws {
        try change(id) { $0.isArchived = isArchived }
    }

    private func change(_ id: Tag.ID, _ apply: (inout Tag) -> Void) throws {
        try stored.withLock { tags in
            guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
            guard !tags[index].isReadOnly else { throw RecordFromNewerVersion() }
            apply(&tags[index])
        }
    }
}
