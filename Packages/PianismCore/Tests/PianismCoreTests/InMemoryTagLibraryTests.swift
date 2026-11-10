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

    @Test("TAG-3: a piece's composer and target tempo are kept, and can be cleared")
    func details() throws {
        let library = InMemoryTagLibrary()
        let ballade = library.add(name: "Ballade", kind: .piece)
        #expect(ballade.composer.isEmpty && ballade.targetTempo == nil)

        try library.setDetails(composer: "Chopin", targetTempo: 72, id: ballade.id)
        #expect(library.tags().map(\.composer) == ["Chopin"])
        #expect(library.tags().map(\.targetTempo) == [72])

        try library.setDetails(composer: "", targetTempo: nil, id: ballade.id)
        #expect(library.tags() == [ballade])
    }

    @Test("ADR 0006: a read-only tag can't be renamed, archived or given details, and an unknown ID changes nothing")
    func readOnlyAndUnknown() throws {
        let newer = PianismCore.Tag(id: "newer", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)
        let library = InMemoryTagLibrary([newer])

        #expect(throws: RecordFromNewerVersion.self) { try library.rename(id: "newer", to: "Etude") }
        #expect(throws: RecordFromNewerVersion.self) { try library.setArchived(true, id: "newer") }
        #expect(throws: RecordFromNewerVersion.self) {
            try library.setDetails(composer: "Chopin", targetTempo: 72, id: "newer")
        }
        try library.rename(id: "unknown", to: "Etude")
        #expect(library.tags() == [newer])
    }

    @Test("TAG-5: a tag added inside another is one new tag with that parent")
    func addInside() {
        // Given
        let library = InMemoryTagLibrary()
        let ballade = library.add(name: "Ballade", kind: .piece)

        // When
        let dMinor = library.add(name: "D minor", kind: .skill, inside: BuiltInSkill.scales.rawValue)

        // Then
        #expect(library.tags() == [ballade, dMinor])
        #expect(dMinor.parentID == BuiltInSkill.scales.rawValue && ballade.parentID == nil)
        #expect(dMinor.name == "D minor" && dMinor.kind == .skill && !dMinor.isArchived && dMinor.id != ballade.id)
    }

    @Test("TAG-5: a tag can be moved inside another and back to the top level, unless a newer version wrote it")
    func setParent() throws {
        // Given
        let newer = PianismCore.Tag(
            id: "newer", kind: .skill, name: "Arpeggios in thirds", isArchived: false,
            isReadOnly: true)
        let library = InMemoryTagLibrary([newer])
        let dMinor = library.add(name: "D minor", kind: .skill)

        // When
        try library.setParent(id: dMinor.id, to: BuiltInSkill.scales.rawValue)
        let inside = library.tags().map(\.parentID)
        try library.setParent(id: dMinor.id, to: nil)

        // Then
        #expect(inside == [nil, BuiltInSkill.scales.rawValue])
        #expect(library.tags() == [newer, dMinor])
        #expect(throws: RecordFromNewerVersion.self) { try library.setParent(id: "newer", to: dMinor.id) }
    }
}
