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
            clock: clock, nudges: InMemoryNudges(), defaults: .standard, nudge: 90 * 60, cap: 4 * 60 * 60)
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

    @Test("TAG-1, ADR 0004: a merged tag's old name offers the tag it was merged into, not the merged one")
    func mergedNameOffersKeptTag() {
        let merged = PianismCore.Tag(
            id: "old", kind: .piece, name: "Chopin G minor", isArchived: true, mergedInto: "ballade")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, merged]))
        model.query = "chopin g minor"

        #expect(model.newName(.piece) == nil)
        #expect(model.shown(.piece) == [ballade])
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

    @Test(
        "TAG-3: a target tempo is empty for none, or a whole number from 20 to 300",
        arguments: [
            ("", true), (" 72 ", true), ("20", true), ("300", true),
            ("19", false), ("301", false), ("7.5", false), ("abc", false), ("-72", false),
        ])
    func tempos(tempo: String, isValid: Bool) {
        let model = TagPickerModel(practice: practice, library: library)

        #expect(model.canSetDetails(tempo: tempo) == isValid)
    }

    @Test("TAG-3: a piece is given a trimmed composer and a tempo, a tempo out of range is refused, and empty clears")
    func setsDetails() throws {
        let model = TagPickerModel(practice: practice, library: library)

        model.setDetails(ballade, composer: " Chopin ", tempo: " 72 ")
        #expect(library.tags().first?.composer == "Chopin")
        #expect(library.tags().first?.targetTempo == 72)

        let detailed = try #require(model.shown(.piece).first)
        model.setDetails(detailed, composer: "Liszt", tempo: "400")
        #expect(library.tags().first?.composer == "Chopin")

        model.setDetails(detailed, composer: " ", tempo: "")
        #expect(library.tags().first == ballade)
        #expect(!model.isShowingError)
    }

    @Test("TAG-3: saving details that didn't change changes nothing, so it can't overtake another device's change")
    func unchangedDetailsAreNotSaved() throws {
        let synced = InMemoryTagLibrary([ballade])
        let model = TagPickerModel(practice: practice, library: synced)
        // Renamed on another device after the picker loaded.
        try synced.rename(id: ballade.id, to: "Ballade No. 1 in G minor")

        model.setDetails(ballade, composer: " ", tempo: "")
        // A save would also reload the picker, showing the rename.
        #expect(model.shown(.piece).map(\.name) == ["Ballade No. 1"])
    }

    @Test(
        "SYN-1: saving one detail keeps the other as another device set it after the details opened",
        arguments: [("Chopin", nil, "", "72"), ("", 72, "Chopin", "")] as [(String, Int?, String, String)])
    func savingOneDetailKeepsTheOther(syncedComposer: String, syncedTempo: Int?, composer: String, tempo: String) throws
    {
        let library = InMemoryTagLibrary([ballade])
        let model = TagPickerModel(practice: practice, library: library)
        try library.setDetails(composer: syncedComposer, targetTempo: syncedTempo, id: ballade.id)

        model.setDetails(ballade, composer: composer, tempo: tempo)
        #expect(library.tags().map { "\($0.composer) \($0.targetTempo ?? 0)" } == ["Chopin 72"])
    }

    @Test(
        "TAG-3: a piece's details read as one line, with only what it has",
        arguments: [
            ("Chopin", 72, "Chopin, 72 BPM"), ("Chopin", nil, "Chopin"), ("", 72, "72 BPM"), ("", nil, nil),
        ] as [(String, Int?, String?)])
    func detailsLine(composer: String, tempo: Int?, line: String?) {
        let tag = PianismCore.Tag(
            id: "ballade", kind: .piece, name: "Ballade No. 1", isArchived: false, composer: composer,
            targetTempo: tempo)

        #expect(tag.details == line)
    }

    @Test("TAG-3: only pieces the user added take details, not skills or read-only tags")
    func onlyOwnPiecesTakeDetails() {
        let model = TagPickerModel(practice: practice, library: library)
        let skill = library.add(name: "Pedalling", kind: .skill)
        let newer = PianismCore.Tag(id: "newer", kind: .piece, name: "Étude", isArchived: false, isReadOnly: true)

        #expect(model.canHaveDetails(ballade))
        #expect(!model.canHaveDetails(skill))
        #expect(!model.canHaveDetails(BuiltInSkill.scales.tag))
        #expect(!model.canHaveDetails(newer))
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
        model.isShowingError = false
        model.setDetails(newer, composer: "Chopin", tempo: "")
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
    func setDetails(composer _: String, targetTempo _: Int?, id _: String) throws { throw Failure() }
}
