import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct TagPickerModelTests {
    let clock = ManualClock()
    let practice: PracticeModel
    let ballade = PianismCore.Tag(id: "ballade", kind: .piece, name: "Ballade No. 1", isArchived: false)
    let nocturne = PianismCore.Tag(id: "nocturne", kind: .piece, name: "Nocturne", isArchived: true)
    let library: InMemoryTagLibrary

    init() {
        practice = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock)
        practice.start()
        library = InMemoryTagLibrary([ballade, nocturne])
    }

    @Test("TAG-1: built-in skills are offered by name, before the user's tags, and can't be renamed or archived")
    func builtInSkillsComeFirst() throws {
        let tags = try library.allTags()

        #expect(
            tags.prefix(6).map(\.name) == [
                "Scales", "Arpeggios", "Technique", "Sight-reading", "Repertoire", "Improvisation",
            ])
        #expect(tags.prefix(6).allSatisfy { $0.kind == .skill && $0.isReadOnly })
        #expect(Array(tags.dropFirst(6)) == [ballade, nocturne])
    }

    @Test("TAG-1, TAG-2: a new piece is added, tags the running session, and clears the query")
    func addsAndTags() throws {
        let model = TagPickerModel(practice: practice, library: library)
        model.query = "  Clair de lune "

        #expect(model.newName(.piece) == "Clair de lune")
        model.add(.piece)

        let added = try #require(library.tags().first { $0.name == "Clair de lune" })
        #expect(model.selected == [added])
        #expect(practice.session?.tagIDs == [added.id])
        #expect(model.query.isEmpty)
        #expect(model.shown(.piece).map(\.name) == ["Ballade No. 1", "Clair de lune"])
    }

    @Test("TAG-1: a name in use, a built-in skill's included, offers that tag instead of adding another")
    func nameInUseOffersTheTag() {
        let model = TagPickerModel(practice: practice, library: library)
        model.query = "SCALES"

        #expect(model.newName(.skill) == nil)
        #expect(model.shown(.skill).map(\.id) == [BuiltInSkill.scales.rawValue])
        // A piece may share a skill's name.
        #expect(model.newName(.piece) == "SCALES")
    }

    @Test("TAG-1: an archived tag shows only when named, and choosing it brings it back and tags the session")
    func archivedTagComesBack() throws {
        let model = TagPickerModel(practice: practice, library: library)
        #expect(model.shown(.piece) == [ballade])

        model.query = "nocturne"
        #expect(model.newName(.piece) == nil)
        #expect(model.shown(.piece) == [nocturne])
        model.toggle(nocturne)

        #expect(library.tags().first { $0.id == nocturne.id }?.isArchived == false)
        #expect(practice.session?.tagIDs == [nocturne.id])
    }

    @Test("TAG-2: choosing a selected tag again removes it, with any tag merged into it, and leaves the rest")
    func toggleOffRemovesMergedTags() {
        let merged = PianismCore.Tag(id: "old", kind: .piece, name: "Ballade", isArchived: true, mergedInto: "ballade")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, merged]))
        practice.setTags(["old", BuiltInSkill.scales.rawValue, "not-synced-yet"])
        #expect(model.selected.map(\.id) == ["ballade", BuiltInSkill.scales.rawValue])

        model.toggle(ballade)

        #expect(practice.session?.tagIDs == [BuiltInSkill.scales.rawValue, "not-synced-yet"])
    }

    @Test("TAG-1: archiving stops offering a tag, except to the session that has it, which keeps it")
    func archiveKeepsSessionTags() {
        let invention = PianismCore.Tag(id: "invention", kind: .piece, name: "Invention", isArchived: false)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, invention]))
        model.toggle(ballade)

        model.archive(ballade)
        model.archive(invention)

        #expect(model.shown(.piece).map(\.id) == ["ballade"])
        #expect(practice.session?.tagIDs == ["ballade"])
    }

    @Test("TAG-1: a tag is renamed, trimmed, but never to nothing or to another of its kind's name")
    func renames() throws {
        let model = TagPickerModel(practice: practice, library: library)

        #expect(!model.canRename(ballade, to: "  "))
        #expect(!model.canRename(ballade, to: "nocturne"))
        #expect(model.canRename(ballade, to: "Scales"))
        #expect(model.canRename(ballade, to: "BALLADE NO. 1"))
        model.rename(ballade, to: "nocturne")
        model.rename(ballade, to: " Ballade No. 1 in G minor ")

        #expect(library.tags().map(\.name) == ["Ballade No. 1 in G minor", "Nocturne"])
        #expect(model.shown(.piece).map(\.name) == ["Ballade No. 1 in G minor"])
    }

    @Test("ADR 0006: a tag that can't be changed, as one a newer version wrote, shows an error, then what's stored")
    func failedChangeShowsErrorAndReloads() {
        let newer = PianismCore.Tag(id: "newer", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)
        let library = InMemoryTagLibrary([newer])
        let model = TagPickerModel(practice: practice, library: library)
        // Arrives from another device after the picker loaded.
        _ = library.add(name: "Synced", kind: .piece)

        model.rename(newer, to: "Etude Op. 10")

        #expect(model.isShowingError)
        #expect(model.shown(.piece).map(\.name) == ["Étude", "Synced"])
    }

    @Test("TAG-1: when the tags can't be reached, the picker says so and the session keeps its tags")
    func unreachableLibraryShowsError() {
        let model = TagPickerModel(practice: practice, library: UnavailableTagLibrary())
        #expect(model.isShowingError)
        model.isShowingError = false
        model.query = "Ballade"

        model.add(.piece)

        #expect(model.isShowingError)
        #expect(practice.session?.tagIDs.isEmpty == true)
    }
}

/// A tag library that can't be reached, as when the store can't open.
private struct UnavailableTagLibrary: TagLibrary {
    struct Failure: Error {}

    func tags() throws -> [PianismCore.Tag] { throw Failure() }
    func add(name _: String, kind _: PianismCore.Tag.Kind) throws -> PianismCore.Tag { throw Failure() }
    func rename(id _: String, to _: String) throws { throw Failure() }
    func setArchived(_: Bool, id _: String) throws { throw Failure() }
}
