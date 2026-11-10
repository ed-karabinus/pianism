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
            clock: clock, nudges: InMemoryNudges(), glance: InMemoryPracticeGlance(), defaults: .standard,
            nudge: 90 * 60, cap: 4 * 60 * 60)
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

    @Test("TAG-4: merging moves a session's tag to the kept one and lists it to undo, which puts both back")
    func mergeAndUndo() throws {
        let duplicate = PianismCore.Tag(id: "dup", kind: .piece, name: "Ballade", isArchived: false)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, duplicate]))
        model.toggle(duplicate)
        model.toggle(ballade)
        let before = try #require(model.selected.first)

        model.merge(duplicate, into: ballade)

        #expect(model.selected.map(\.id) == ["ballade"])
        #expect(practice.session?.tagIDs == ["dup", "ballade"], "A session is never rewritten")
        #expect(model.shown(.piece).map(\.id) == ["ballade"])
        #expect(model.merged.map(\.tag.id) == ["dup"])
        #expect(model.merged.map(\.kept.id) == ["ballade"])

        model.undoMerge(try #require(model.merged.first?.tag))

        #expect(model.selected.map(\.id) == ["dup", "ballade"])
        #expect(model.selected.first == before)
        #expect(model.shown(.piece).map(\.id) == ["dup", "ballade"])
        #expect(model.merged.isEmpty)
    }

    @Test("TAG-4: a tag merges into others of its kind on offer, built-in skills too, and a merged one isn't offered")
    func mergeTargets() {
        let piece = PianismCore.Tag(id: "piece", kind: .piece, name: "Etude", isArchived: false)
        let skill = PianismCore.Tag(id: "skill", kind: .skill, name: "Pedalling", isArchived: false)
        let merged = PianismCore.Tag(id: "old", kind: .piece, name: "Old", isArchived: true, mergedInto: "ballade")
        let zeta = PianismCore.Tag(id: "zeta", kind: .piece, name: "Zeta", isArchived: false)
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([zeta, piece, ballade, nocturne, merged, skill]))

        #expect(model.mergeTargets(for: piece).map(\.id) == ["ballade", "zeta"], "By name, without the tag itself")
        #expect(model.mergeTargets(for: skill).count == BuiltInSkill.allCases.count)
        #expect(model.mergeTargets(for: skill).contains { $0.id == BuiltInSkill.scales.rawValue })
    }

    @Test("TAG-4: only a user's tag that's on offer, with another to merge into, can be merged")
    func canMerge() throws {
        let readOnly = PianismCore.Tag(id: "new", kind: .piece, name: "Newer", isArchived: false, isReadOnly: true)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, nocturne, readOnly]))
        let alone = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, nocturne]))

        #expect(model.canMerge(ballade))
        #expect(!model.canMerge(nocturne), "Undoing would unarchive it")
        #expect(!model.canMerge(readOnly), "A newer version wrote it")
        #expect(!model.canMerge(BuiltInSkill.scales.tag), "It has no record")
        #expect(!alone.canMerge(ballade), "Nothing to merge it into: the other is archived")
    }

    @Test("TAG-4: Merged is hidden while searching, and a tag waiting for its kept tag to sync isn't in it")
    func mergedList() {
        let merged = PianismCore.Tag(id: "old", kind: .piece, name: "Old", isArchived: true, mergedInto: "ballade")
        let waiting = PianismCore.Tag(id: "wait", kind: .piece, name: "Wait", isArchived: true, mergedInto: "later")
        let earlier = PianismCore.Tag(id: "e", kind: .piece, name: "Earlier", isArchived: true, mergedInto: "ballade")
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([ballade, merged, waiting, earlier]))

        #expect(model.merged.map(\.tag.id) == ["e", "old"], "By name")
        model.query = "Ballade"
        #expect(model.merged.isEmpty)
    }

    @Test("TAG-4: after opposite merges the tag they settled on is offered and the other can be undone, twice to split")
    func oppositeMerges() throws {
        let first = PianismCore.Tag(
            id: "first", kind: .piece, name: "First", isArchived: false, createdAt: .distantPast)
        let second = PianismCore.Tag(id: "second", kind: .piece, name: "Second", isArchived: false, createdAt: .now)
        let library = InMemoryTagLibrary([first, second])
        let model = TagPickerModel(practice: practice, library: library)
        try library.merge(id: "first", into: "second")
        try library.merge(id: "second", into: "first")
        model.refresh()

        #expect(model.shown(.piece).map(\.id) == ["first"])
        #expect(model.shown(.piece).first?.isArchived == false)
        model.query = "Fir"
        #expect(model.shown(.piece).map(\.id) == ["first"], "Search finds it too")
        model.query = ""
        #expect(model.merged.map(\.tag.id) == ["second"])

        model.undoMerge(second)

        #expect(model.shown(.piece).map(\.id) == ["second"], "The other device's merge still stands")
        #expect(model.merged.map(\.tag.id) == ["first"])

        model.undoMerge(first)

        #expect(model.shown(.piece).map(\.id) == ["first", "second"])
        #expect(model.merged.isEmpty)
    }

    @Test("TAG-4: the kept tag can take a merged tag's name, but not a name that's still on offer or archived")
    func renameToAMergedName() {
        let merged = PianismCore.Tag(id: "old", kind: .piece, name: "Old", isArchived: true, mergedInto: "ballade")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, nocturne, merged]))

        #expect(model.canRename(ballade, to: "Old"))
        #expect(!model.canRename(ballade, to: "Nocturne"))
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

    @Test("TAG-1: an archived tag shows only when searched for, and choosing it brings it back and tags the session")
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

    @Test("TAG-1: part of a name finds archived tags too, after unarchived ones, but never a merged tag's old name")
    func searchFindsArchivedTags() {
        let opus = PianismCore.Tag(id: "opus", kind: .piece, name: "Nocturne Op. 9", isArchived: false)
        let merged = PianismCore.Tag(
            id: "old", kind: .piece, name: "Nocturne in E minor", isArchived: true, mergedInto: "ballade")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, nocturne, opus, merged]))
        model.query = "noct"

        #expect(model.shown(.piece) == [opus, nocturne])
        #expect(model.newName(.piece) == "noct")
        model.query = "turne"
        #expect(model.shown(.piece) == [opus, nocturne])
        model.query = "Nocturne in E minor"
        #expect(model.shown(.piece) == [ballade])
        #expect(model.newName(.piece) == nil)
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

    @Test("TAG-5, D3: a parent opens folded, unfolded if one of its children is chosen, and then as the user folds it")
    func folding() {
        // Given a skill inside Scales, chosen, and one inside Arpeggios, not chosen
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let cMajor = skill("c-major", "C major", inside: .arpeggios)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([dMinor, cMajor]))
        let scales = BuiltInSkill.scales.rawValue
        let arpeggios = BuiltInSkill.arpeggios.rawValue
        model.toggle(dMinor)

        // When the picker opens
        model.open()

        // Then only Scales is unfolded, until the user folds it
        #expect(model[isUnfolded: scales])
        #expect(!model[isUnfolded: arpeggios])
        model[isUnfolded: scales] = false
        model.toggle(cMajor)
        #expect(!model[isUnfolded: scales])
        #expect(!model[isUnfolded: arpeggios], "Choosing a child while open doesn't unfold its parent")
    }

    @Test("TAG-5, D3: children fold under their parent, archived ones only if chosen, and a search lists them flat")
    func childrenFoldUnderTheParent() {
        // Given Scales with a live and an archived skill inside it, and a top-level skill
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let old = skill("old", "A minor", inside: .scales, archived: true)
        let pedalling = skill("pedalling", "Pedalling")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([dMinor, old, pedalling]))
        let scales = BuiltInSkill.scales.tag

        // When the picker shows its skills
        let topLevel = model.shown(.skill).map(\.id)

        // Then the children are under Scales, not at the top level
        #expect(!topLevel.contains("d-minor"))
        #expect(topLevel.contains("pedalling") && topLevel.contains(scales.id))
        #expect(model.shown(inside: scales).map(\.id) == ["d-minor"])
        #expect(model.label(dMinor) == "D minor")
        // Tagged before it was archived, which choosing it in the picker would undo.
        practice.setTags(["old"])
        #expect(model.shown(inside: scales).map(\.id) == ["d-minor", "old"], "A chosen archived child shows, last")

        // When the user searches for part of a child's name
        model.query = "minor"

        // Then each hit is listed on its own, a child named with its parent, and nothing is folded under Scales
        #expect(model.shown(.skill).map(\.id) == ["d-minor", "old"])
        #expect(model.label(dMinor) == "Scales › D minor")
        #expect(model.shown(inside: scales).isEmpty)
    }

    @Test(
        "TAG-5, D4: a skill added inside a built-in is stored in it, tags the session, unfolds it and clears a search")
    func addsInside() throws {
        // Given the picker, closed folds, an untagged session and a search that matches Scales but not the new name
        let model = TagPickerModel(practice: practice, library: library)
        let scales = BuiltInSkill.scales.tag
        model.open()
        model.query = "Scal"

        // When "D minor" is added inside Scales
        model.add(" D minor ", inside: scales)

        // Then the search is cleared, so it isn't hidden, and it's one record inside Scales, the session's tag, read
        // as "Scales › D minor", under an open Scales
        #expect(model.query.isEmpty)
        let added = try #require(library.tags().first { $0.name == "D minor" })
        #expect(added.parentID == scales.id)
        #expect(added.kind == .skill)
        #expect(practice.session?.tagIDs == [added.id])
        #expect(model.selectedNames == ["Scales › D minor"])
        #expect(model[isUnfolded: scales.id])
        #expect(model.shown(inside: scales).map(\.id) == [added.id])
    }

    @Test("TAG-5, D5: the session's tags read with their parents, and a parent as itself")
    func selectedNames() {
        // Given a session tagged with a piece, a skill inside Scales, and Scales
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, dMinor]))
        practice.setTags(["ballade", "d-minor", BuiltInSkill.scales.rawValue])

        // When its tags are named
        let names = model.selectedNames

        // Then the child carries its parent's name, and nothing else does
        #expect(names == ["Ballade No. 1", "Scales › D minor", "Scales"])
    }

    @Test("TAG-5, Q1, ADR 0013: a list is read as shown, so a child of a tag merged away is in the kept tag's list")
    func listsAreReadThroughMerges() {
        // Given "D minor" inside a skill that another device merged into Technique
        let merged = skill("left-hand", "Left hand", archived: true)
        let dMinor = skill("d-minor", "D minor")
        let library = InMemoryTagLibrary([
            PianismCore.Tag(
                id: merged.id, kind: .skill, name: merged.name, isArchived: true,
                mergedInto: BuiltInSkill.technique.rawValue),
            PianismCore.Tag(id: dMinor.id, kind: .skill, name: dMinor.name, isArchived: false, parentID: merged.id),
        ])
        let model = TagPickerModel(practice: practice, library: library)
        let technique = BuiltInSkill.technique.tag

        // When a name is checked inside Technique
        // Then the child it now shows inside Technique has the name
        #expect(model.shown(inside: technique).map(\.id) == ["d-minor"])
        #expect(!model.canAdd("D minor", inside: technique))
    }

    @Test("TAG-5: only a top-level tag on offer, a built-in skill too, can have a tag added inside it")
    func addInsideEligibility() {
        // Given a top-level piece, a skill inside Scales and an archived skill
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let archived = skill("old", "Old", archived: true)
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([ballade, dMinor, archived]))

        // When each is asked whether it can take a tag inside it
        // Then the top-level ones can, and a child or an archived tag can't
        #expect(model.canAddInside(ballade))
        #expect(model.canAddInside(BuiltInSkill.scales.tag))
        #expect(!model.canAddInside(dMinor), "Tags nest one level deep")
        #expect(!model.canAddInside(archived))
        #expect(!model.canAdd("Rubato", inside: dMinor))
    }

    @Test("TAG-5, ADR 0013: a tag that reads top-level but has a stored link can't have a tag added inside it")
    func addInsideNeedsNoStoredLink() {
        // Given a piece inside a tag that hasn't synced to this device yet, so it reads top-level
        let waiting = PianismCore.Tag(
            id: "waiting", kind: .piece, name: "Waiting", isArchived: false, parentID: "unseen")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([waiting]))

        // When it's asked whether it can take a tag inside it
        // Then it can't, though it's listed at the top level: once its parent syncs, the new tag would be a grandchild
        #expect(model.shown(.piece).map(\.id) == ["waiting"])
        #expect(!model.canAddInside(waiting))
        #expect(!model.canAdd("Prelude", inside: waiting))
    }

    @Test("TAG-5, Q1: a name is unique within its list, folding case and accents, and free in another list")
    func namesAreUniquePerList() {
        // Given "D minor" inside Scales, "Étude" inside Ballade, and a top-level skill
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let gMajor = skill("g-major", "G major", inside: .scales)
        let etude = PianismCore.Tag(id: "etude", kind: .piece, name: "Étude", isArchived: false, parentID: "ballade")
        let pedalling = skill("pedalling", "Pedalling")
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([ballade, etude, dMinor, gMajor, pedalling]))
        let scales = BuiltInSkill.scales.tag

        // When names are checked in each list
        // Then a clash within a list is refused, and the same name in another list is allowed
        #expect(!model.canAdd("d MINOR", inside: scales))
        #expect(!model.canAdd("etude", inside: ballade))
        #expect(!model.canAdd("  ", inside: scales))
        #expect(model.canAdd("D minor", inside: BuiltInSkill.arpeggios.tag))
        #expect(model.canAdd("Pedalling", inside: scales))
        #expect(!model.canRename(gMajor, to: "D Minor"))
        #expect(model.canRename(gMajor, to: "Pedalling"))
        #expect(model.canRename(pedalling, to: "D minor"))
        #expect(!model.canRename(pedalling, to: "Arpeggios"), "Built-in skills are in the top-level list")
        model.query = "d minor"
        #expect(model.newName(.skill) == "d minor", "No top-level skill has the name")
        model.query = "ARPEGGIOS"
        #expect(model.newName(.skill) == nil)
    }

    @Test("TAG-5: a child can't share its parent's name, folding case and accents, when added or renamed")
    func childNotNamedLikeItsParent() {
        // Given "D minor" inside the built-in Scales, and "Étude" inside a piece named "Etude"
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let etudes = PianismCore.Tag(id: "etudes", kind: .piece, name: "Etude", isArchived: false)
        let first = PianismCore.Tag(id: "first", kind: .piece, name: "No. 1", isArchived: false, parentID: "etudes")
        let model = TagPickerModel(practice: practice, library: InMemoryTagLibrary([dMinor, etudes, first]))
        let scales = BuiltInSkill.scales.tag

        // When a child is given its parent's name, by adding or by renaming either one
        // Then it's refused, and a name only like the parent's is allowed
        #expect(!model.canAdd("Scales", inside: scales))
        #expect(!model.canAdd(" scales ", inside: scales))
        #expect(!model.canAdd("ÉTUDE", inside: etudes))
        #expect(model.canAdd("Scales in thirds", inside: scales))
        #expect(!model.canRename(dMinor, to: "Scales"))
        #expect(!model.canRename(first, to: "étude"))
        #expect(!model.canRename(etudes, to: "no. 1"), "Its child would share its new name")
        #expect(model.canRename(etudes, to: "Études"))
    }

    @Test(
        "TAG-5, D1: a parent with something unarchived inside can't be archived until it's archived; archived don't count"
    )
    func archiveWaitsForWhatsInside() throws {
        // Given a piece with two unarchived pieces and an archived one inside it
        let inside = ["no-1", "no-2"].map {
            PianismCore.Tag(id: $0, kind: .piece, name: $0, isArchived: false, parentID: "ballade")
        }
        let old = PianismCore.Tag(id: "old", kind: .piece, name: "Old", isArchived: true, parentID: "ballade")
        let library = InMemoryTagLibrary([ballade] + inside + [old])
        let model = TagPickerModel(practice: practice, library: library)

        // When the parent is archived
        #expect(model.liveChildren(of: ballade) == 2)
        model.archive(ballade)

        // Then it stays on offer
        #expect(library.tags().first?.isArchived == false)

        // When what's inside is archived, then the parent
        model.archive(inside[0])
        #expect(model.liveChildren(of: ballade) == 1)
        model.archive(inside[1])
        model.archive(ballade)

        // Then it's archived
        #expect(model.liveChildren(of: ballade) == 0)
        #expect(library.tags().first?.isArchived == true)
    }

    @Test("TAG-5, D2: a tag merges only within its list, into a tag with nothing inside, and a parent can't merge")
    func mergeStaysInOneList() {
        // Given two pieces inside Ballade, one inside another piece, a parent whose only child is archived, and two
        // top-level pieces without children
        let first = PianismCore.Tag(id: "first", kind: .piece, name: "First", isArchived: false, parentID: "ballade")
        let second = PianismCore.Tag(id: "second", kind: .piece, name: "Second", isArchived: false, parentID: "ballade")
        let cousin = PianismCore.Tag(id: "cousin", kind: .piece, name: "Cousin", isArchived: false, parentID: "suite")
        let suite = PianismCore.Tag(id: "suite", kind: .piece, name: "Suite", isArchived: false)
        let emptied = PianismCore.Tag(id: "emptied", kind: .piece, name: "Emptied", isArchived: false)
        let gone = PianismCore.Tag(id: "gone", kind: .piece, name: "Gone", isArchived: true, parentID: "emptied")
        let lone = PianismCore.Tag(id: "lone", kind: .piece, name: "Lone", isArchived: false)
        let twin = PianismCore.Tag(id: "twin", kind: .piece, name: "Lone", isArchived: false)
        let model = TagPickerModel(
            practice: practice,
            library: InMemoryTagLibrary([ballade, first, second, suite, cousin, emptied, gone, lone, twin]))

        // When each is asked what it can merge into
        // Then a child merges only into its siblings, a top-level tag only into childless top-level ones, and a
        // parent, even of only archived tags, into nothing
        #expect(model.mergeTargets(for: first).map(\.id) == ["second"])
        #expect(model.mergeTargets(for: lone).map(\.id) == ["twin"], "Two duplicates from un-nesting can merge")
        #expect(model.canMerge(first))
        #expect(!model.canMerge(ballade))
        #expect(!model.canMerge(emptied), "Archived children count")
        #expect(!model.mergeTargets(for: cousin).contains { $0.id == "first" })
    }

    @Test("TAG-5, D4: a tag moves inside top-level tags of its kind on offer, built-ins too, not a child or itself")
    func moveTargets() {
        // Given a skill inside Scales, a top-level skill, an archived one, a merged one left unarchived, and a piece
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let gMajor = skill("g-major", "G major", inside: .scales)
        let pedalling = skill("pedalling", "Pedalling")
        let old = skill("old", "Old", archived: true)
        let merged = PianismCore.Tag(id: "dup", kind: .skill, name: "Dup", isArchived: false, mergedInto: "pedalling")
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([ballade, dMinor, gMajor, pedalling, old, merged]))

        // When each is asked where it can go
        let targets = model.moveTargets(for: dMinor).map(\.id)

        // Then it's the top-level skills on offer by name, its own parent included, and never the tag itself
        #expect(
            targets == [
                "skill.arpeggios", "skill.improvisation", "pedalling", "skill.repertoire", "skill.scales",
                "skill.sight-reading", "skill.technique",
            ])
        #expect(!model.moveTargets(for: pedalling).contains { $0.id == "pedalling" })
        #expect(model.moveTargets(for: ballade).isEmpty, "No other piece, and skills are another kind")
    }

    @Test("TAG-5, D4: a user's tag with nothing inside it and somewhere to go can move; not a parent or a built-in")
    func canMove() {
        // Given a piece whose only piece inside is archived, a top-level piece, a read-only one, and a skill
        let gone = PianismCore.Tag(id: "gone", kind: .piece, name: "Gone", isArchived: true, parentID: "ballade")
        let suite = PianismCore.Tag(id: "suite", kind: .piece, name: "Suite", isArchived: false)
        let newer = PianismCore.Tag(id: "newer", kind: .piece, name: "Newer", isArchived: false, isReadOnly: true)
        let pedalling = skill("pedalling", "Pedalling")
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([ballade, gone, suite, newer, pedalling]))
        let alone = TagPickerModel(practice: practice, library: InMemoryTagLibrary([suite]))

        // When each is asked whether it can move
        // Then only a user's own tag without anything inside it, with somewhere to go, can
        #expect(model.canMove(suite))
        #expect(model.canMove(pedalling))
        #expect(model.canMove(gone), "A child can go to the top level")
        #expect(!model.canMove(ballade), "It would take what's inside to a second level, archived or not")
        #expect(!model.canMove(BuiltInSkill.scales.tag), "Built-in skills are never children")
        #expect(!model.canMove(newer))
        #expect(!alone.canMove(suite), "Nowhere to go")
    }

    @Test(
        "TAG-5, D4: a skill moved inside Scales and back reads there, unfolded, and its sessions follow without a write"
    )
    func movesInsideAndBack() {
        // Given a session tagged with a top-level skill
        let pedalling = skill("pedalling", "Pedalling")
        let library = InMemoryTagLibrary([pedalling])
        let model = TagPickerModel(practice: practice, library: library)
        let scales = BuiltInSkill.scales.tag
        practice.setTags(["pedalling"])

        // When it's moved inside Scales
        model.move(pedalling, to: scales)

        // Then it's stored and read inside Scales, and the session still names it alone
        #expect(library.tags().first?.parentID == scales.id)
        #expect(model.parent(of: pedalling)?.id == scales.id)
        #expect(model[isUnfolded: scales.id], "Scales stayed folded, hiding it")
        #expect(model.selectedNames == ["Scales › Pedalling"])
        #expect(practice.session?.tagIDs == ["pedalling"])

        // When it's moved back to the top level
        model.move(pedalling, to: nil)

        // Then it's at the top level again
        #expect(library.tags().first?.parentID == nil)
        #expect(model.selectedNames == ["Pedalling"])
        #expect(practice.session?.tagIDs == ["pedalling"])
    }

    @Test("TAG-5, ADR 0013: choosing where a tag reads already writes nothing, so a tag two deep keeps its own link")
    func movingToTheCurrentPlaceDoesNothing() {
        // Given D inside C, which another device put inside P, so D reads at the top level
        let parent = PianismCore.Tag(id: "p", kind: .piece, name: "P", isArchived: false)
        let middle = PianismCore.Tag(id: "c", kind: .piece, name: "C", isArchived: false, parentID: "p")
        let grandchild = PianismCore.Tag(id: "d", kind: .piece, name: "D", isArchived: false, parentID: "c")
        let library = InMemoryTagLibrary([parent, middle, grandchild])
        let model = TagPickerModel(practice: practice, library: library)
        #expect(model.parent(of: grandchild) == nil)

        // When D is moved to the top level, where it reads
        model.move(grandchild, to: nil)

        // Then its link stays, so moving C out puts D back inside C (ADR 0013)
        #expect(library.tags().last?.parentID == "c")
        model.move(middle, to: nil)
        #expect(model.parent(of: grandchild)?.id == "c")
    }

    @Test(
        "TAG-5, Q1: a move into a list with a tag of its name is refused with the reason, both ways, case and accents")
    func moveRefusesANameClash() {
        // Given "D minor" inside Scales and a top-level "d minor", "Étude" inside Ballade and a top-level "etude"
        let dMinor = skill("d-minor", "D minor", inside: .scales)
        let twin = skill("twin", "d minor")
        let etude = PianismCore.Tag(id: "etude", kind: .piece, name: "Étude", isArchived: false, parentID: "ballade")
        let loose = PianismCore.Tag(id: "loose", kind: .piece, name: "etude", isArchived: false)
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([ballade, etude, loose, dMinor, twin]))
        let scales = BuiltInSkill.scales.tag

        // When each would move into the other's list
        // Then each is refused with its reason, and another list is fine
        #expect(
            model.moveRefusal(dMinor, to: nil)
                == "A skill named “D minor” is already at the top level. Rename one first.")
        #expect(
            model.moveRefusal(twin, to: scales)
                == "A skill named “d minor” is already inside “Scales”. Rename one first.")
        #expect(model.moveRefusal(twin, to: BuiltInSkill.arpeggios.tag) == nil)
        #expect(
            model.moveRefusal(etude, to: nil) == "A piece named “Étude” is already at the top level. Rename one first.")
        #expect(
            model.moveRefusal(loose, to: ballade)
                == "A piece named “etude” is already inside “Ballade No. 1”. Rename one first.")

        // When the moves are tried anyway
        model.move(dMinor, to: nil)
        model.move(loose, to: ballade)

        // Then nothing moved
        #expect(model.parent(of: dMinor)?.id == scales.id)
        #expect(model.parent(of: loose) == nil)

        // When one of a pair is renamed
        model.rename(twin, to: "D minor, left hand")
        model.move(dMinor, to: nil)

        // Then the move goes through
        #expect(model.parent(of: dMinor) == nil)
    }

    @Test("TAG-5: a move inside a tag of the same name, case and accents aside, is refused with the reason")
    func moveRefusesTheParentsName() {
        // Given a top-level skill named "scales" and a top-level piece "Étude", beside a piece "Etude"
        let lowerScales = skill("lower-scales", "scales")
        let etude = PianismCore.Tag(id: "etude", kind: .piece, name: "Étude", isArchived: false)
        let etudes = PianismCore.Tag(id: "etudes", kind: .piece, name: "Etude", isArchived: false)
        let library = InMemoryTagLibrary([lowerScales, etude, etudes])
        let model = TagPickerModel(practice: practice, library: library)

        // When each would move inside the tag of its name
        // Then it's refused with its reason, and moving elsewhere is fine
        #expect(
            model.moveRefusal(lowerScales, to: BuiltInSkill.scales.tag)
                == "A skill can't sit inside one with the same name. Rename one first.")
        #expect(
            model.moveRefusal(etude, to: etudes) == "A piece can't sit inside one with the same name. Rename one first."
        )
        #expect(model.moveRefusal(lowerScales, to: BuiltInSkill.arpeggios.tag) == nil)

        // When the move is tried anyway
        model.move(etude, to: etudes)

        // Then nothing moved
        #expect(library.tags().allSatisfy { $0.parentID == nil })
    }

    @Test("TAG-5, ADR 0013: moving the loser of a mutual nesting out clears the winner's link, so it stays on top")
    func movingOutClearsTheLatentLink() {
        // Given A and B, each put inside the other on two devices, A older, so B reads inside A
        let older = PianismCore.Tag(
            id: "a", kind: .piece, name: "A", isArchived: false, parentID: "b",
            createdAt: Date(timeIntervalSince1970: 1))
        let newer = PianismCore.Tag(
            id: "b", kind: .piece, name: "B", isArchived: false, parentID: "a",
            createdAt: Date(timeIntervalSince1970: 2))
        let library = InMemoryTagLibrary([older, newer])
        let model = TagPickerModel(practice: practice, library: library)
        #expect(model.parent(of: newer)?.id == "a")

        // When B is moved to the top level
        model.move(newer, to: nil)

        // Then both links are cleared, and both read at the top level
        #expect(library.tags().map(\.parentID) == [nil, nil])
        #expect(model.parent(of: older) == nil)
        #expect(model.parent(of: newer) == nil)
    }

    @Test("TAG-5, ADR 0013: a move leaves a parent's link alone when it names another tag, and clears one it joins")
    func movingClearsOnlyALinkToTheMovedTag() {
        // Given C inside P, whose own link names a tag not synced yet, and Q, newer than C, which another device put
        // inside C, so Q reads at the top level while C is inside P
        let parent = PianismCore.Tag(id: "p", kind: .piece, name: "P", isArchived: false, parentID: "unsynced")
        let child = PianismCore.Tag(
            id: "c", kind: .piece, name: "C", isArchived: false, parentID: "p",
            createdAt: Date(timeIntervalSince1970: 1))
        let other = PianismCore.Tag(
            id: "q", kind: .piece, name: "Q", isArchived: false, parentID: "c",
            createdAt: Date(timeIntervalSince1970: 2))
        let library = InMemoryTagLibrary([parent, child, other])
        let model = TagPickerModel(practice: practice, library: library)

        // When C is moved inside Q
        model.move(child, to: other)

        // Then P keeps its link, Q's link to C is cleared, and C reads inside Q though it's older
        #expect(library.tags().map(\.parentID) == ["unsynced", "q", nil])
        #expect(model.parent(of: child)?.id == "q")
    }

    @Test("TAG-5, ADR 0013: a top-level tag whose own link names another isn't offered, unless it names the moved one")
    func moveTargetsLeaveOutALinkedTag() {
        // Given X inside C inside P, A and B inside each other with A older, so A wins, a ring of R, S and T, and M
        let child = piece("c", inside: "p")
        let loser = piece("b", inside: "a", created: 2)
        let ring = piece("r", inside: "s")
        let mover = piece("m")
        let model = TagPickerModel(
            practice: practice,
            library: InMemoryTagLibrary([
                piece("p"), child, piece("x", inside: "c"), piece("a", inside: "b", created: 1), loser, ring,
                piece("s", inside: "t"), piece("t", inside: "r"), mover,
            ]))

        // When each is asked where it can go
        let targets = { (tag: PianismCore.Tag) in model.moveTargets(for: tag).map(\.id) }

        // Then the grandchild, the winner and the ring, which read top-level, are offered only to the tag they name
        #expect(targets(mover) == ["p"], "A tag moved inside one of them would read top-level too")
        #expect(targets(child).contains("x"))
        #expect(targets(loser).contains("a"), "Its own parent")
        #expect(targets(ring).contains("t") && !targets(ring).contains("s"))
    }

    @Test("TAG-5, ADR 0013: a tag whose own parent hasn't synced isn't offered, except to a tag already inside it")
    func moveTargetsLeaveOutATagWaitingForItsParent() {
        // Given W, whose parent hasn't synced, with C inside it, and M
        let waiting = piece("w", inside: "unsynced")
        let inside = piece("c", inside: "w")
        let mover = piece("m")
        let model = TagPickerModel(
            practice: practice, library: InMemoryTagLibrary([waiting, inside, mover, piece("p")]))

        // When each is asked where it can go
        let targets = { (tag: PianismCore.Tag) in model.moveTargets(for: tag).map(\.id) }

        // Then W isn't offered to M, as M would read top-level once W's parent arrives, but C still sees where it is
        #expect(!targets(mover).contains("w"))
        #expect(targets(inside).contains("w"))
    }

    @Test("TAG-5, ADR 0013: a move inside a tag that isn't offered writes nothing")
    func movingInsideATagNotOfferedWritesNothing() {
        // Given X inside C inside P, so X reads top-level, and M
        let library = InMemoryTagLibrary([piece("p"), piece("c", inside: "p"), piece("x", inside: "c"), piece("m")])
        let model = TagPickerModel(practice: practice, library: library)
        let before = library.tags()

        // When M is moved inside X anyway
        model.move(piece("m"), to: piece("x", inside: "c"))

        // Then nothing is written
        #expect(library.tags() == before)
    }

    @Test("TAG-5, ADR 0013: if clearing the winner's link fails, the move writes nothing more, so neither tag jumps")
    func aFailedClearLeavesThePairAsItWas() {
        // Given B inside A after a mutual nesting, and a library that can't change A
        let older = piece("a", inside: "b", created: 1)
        let newer = piece("b", inside: "a", created: 2)
        let library = TagLibraryFailingOn("a", InMemoryTagLibrary([older, newer]))
        let model = TagPickerModel(practice: practice, library: library)

        // When B is moved to the top level
        model.move(newer, to: nil)

        // Then it says so, and B is still inside A, rather than A inside B
        #expect(model.isShowingError)
        #expect(model.parent(of: newer)?.id == "a")
        #expect(model.parent(of: older) == nil)
    }

    private func piece(_ id: String, inside parent: String? = nil, created: TimeInterval = 0) -> PianismCore.Tag {
        PianismCore.Tag(
            id: id, kind: .piece, name: id.uppercased(), isArchived: false, parentID: parent,
            createdAt: Date(timeIntervalSince1970: created))
    }

    private func skill(
        _ id: String, _ name: String, inside parent: BuiltInSkill? = nil, archived: Bool = false
    ) -> PianismCore.Tag {
        PianismCore.Tag(id: id, kind: .skill, name: name, isArchived: archived, parentID: parent?.rawValue)
    }
}

/// A tag library whose `setParent` fails for one tag, as when a write to it doesn't save, to see what the other write
/// of a move leaves.
private struct TagLibraryFailingOn: TagLibrary {
    private let failing: PianismCore.Tag.ID
    private let library: InMemoryTagLibrary

    init(_ failing: PianismCore.Tag.ID, _ library: InMemoryTagLibrary) {
        self.failing = failing
        self.library = library
    }

    func tags() throws -> [PianismCore.Tag] { library.tags() }
    func add(name: String, kind: PianismCore.Tag.Kind) throws -> PianismCore.Tag { library.add(name: name, kind: kind) }
    func add(name: String, kind: PianismCore.Tag.Kind, inside parent: String) throws -> PianismCore.Tag {
        library.add(name: name, kind: kind, inside: parent)
    }
    func rename(id: String, to name: String) throws { try library.rename(id: id, to: name) }
    func setArchived(_ isArchived: Bool, id: String) throws { try library.setArchived(isArchived, id: id) }
    func setDetails(composer: String, targetTempo: Int?, id: String) throws {
        try library.setDetails(composer: composer, targetTempo: targetTempo, id: id)
    }
    func merge(id: String, into kept: String) throws { try library.merge(id: id, into: kept) }
    func unmerge(id: String) throws { try library.unmerge(id: id) }
    func setParent(id: String, to parent: String?) throws {
        guard id != failing else { throw UnavailableTagLibrary.Failure() }
        try library.setParent(id: id, to: parent)
    }
}

/// A tag library that can't be reached, as when the store can't open.
private struct UnavailableTagLibrary: TagLibrary {
    struct Failure: Error {}

    func tags() throws -> [PianismCore.Tag] { throw Failure() }
    func add(name _: String, kind _: PianismCore.Tag.Kind) throws -> PianismCore.Tag { throw Failure() }
    func add(name _: String, kind _: PianismCore.Tag.Kind, inside _: String) throws -> PianismCore.Tag {
        throw Failure()
    }
    func rename(id _: String, to _: String) throws { throw Failure() }
    func setArchived(_: Bool, id _: String) throws { throw Failure() }
    func setDetails(composer _: String, targetTempo _: Int?, id _: String) throws { throw Failure() }
    func merge(id _: String, into _: String) throws { throw Failure() }
    func unmerge(id _: String) throws { throw Failure() }
    func setParent(id _: String, to _: String?) throws { throw Failure() }
}
