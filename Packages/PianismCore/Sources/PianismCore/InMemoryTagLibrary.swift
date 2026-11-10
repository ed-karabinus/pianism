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
        add(Tag(id: UUID().uuidString.lowercased(), kind: kind, name: name, isArchived: false))
    }

    public func add(name: String, kind: Tag.Kind, inside parent: Tag.ID) -> Tag {
        add(Tag(id: UUID().uuidString.lowercased(), kind: kind, name: name, isArchived: false, parentID: parent))
    }

    private func add(_ tag: Tag) -> Tag {
        stored.withLock { $0.append(tag) }
        return tag
    }

    public func rename(id: Tag.ID, to name: String) throws {
        try change(id) { $0.name = name }
    }

    public func setArchived(_ isArchived: Bool, id: Tag.ID) throws {
        try change(id) { $0.isArchived = isArchived }
    }

    public func setDetails(composer: String, targetTempo: Int?, id: Tag.ID) throws {
        try change(id) {
            $0.composer = composer
            $0.targetTempo = targetTempo
        }
    }

    public func merge(id: Tag.ID, into kept: Tag.ID) throws {
        try change(id) {
            $0.mergedInto = kept
            $0.isArchived = true
        }
    }

    public func unmerge(id: Tag.ID) throws {
        try change(id) {
            $0.mergedInto = nil
            $0.isArchived = false
        }
    }

    public func setParent(id: Tag.ID, to parent: Tag.ID?) throws {
        try change(id) { $0.parentID = parent }
    }

    private func change(_ id: Tag.ID, _ apply: (inout Tag) -> Void) throws {
        try stored.withLock { tags in
            guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
            guard !tags[index].isReadOnly else { throw RecordFromNewerVersion() }
            apply(&tags[index])
        }
    }
}
