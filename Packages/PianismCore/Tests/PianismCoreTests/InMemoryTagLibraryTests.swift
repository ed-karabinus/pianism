import PianismCore
import Testing

/// The ``TagLibrary`` contract, checked on the fake that previews and view-model tests rely on.
struct InMemoryTagLibraryTests {
    @Test("TAG-1: added tags can be renamed, archived and brought back, each change kept")
    func addRenameArchive() throws {
        let library = InMemoryTagLibrary()
        let ballade = library.add(name: "Ballade", kind: .piece)
        let scales = library.add(name: "Scales in thirds", kind: .skill)
        #expect(library.tags() == [ballade, scales])
        #expect(!ballade.isArchived && !ballade.isReadOnly && ballade.id == ballade.id.lowercased())
        #expect(ballade.id != scales.id)

        try library.rename(id: ballade.id, to: "Ballade No. 1")
        try library.setArchived(true, id: scales.id)
        #expect(library.tags().map(\.name) == ["Ballade No. 1", "Scales in thirds"])
        #expect(library.tags().map(\.isArchived) == [false, true])

        try library.setArchived(false, id: scales.id)
        #expect(library.tags().map(\.isArchived) == [false, false])
    }

    @Test("ADR 0006: a read-only tag can't be renamed or archived, and an unknown ID changes nothing")
    func readOnlyAndUnknown() throws {
        let newer = PianismCore.Tag(id: "newer", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)
        let library = InMemoryTagLibrary([newer])

        #expect(throws: RecordFromNewerVersion.self) { try library.rename(id: "newer", to: "Etude") }
        #expect(throws: RecordFromNewerVersion.self) { try library.setArchived(true, id: "newer") }
        try library.rename(id: "unknown", to: "Etude")
        #expect(library.tags() == [newer])
    }
}
