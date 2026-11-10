import Foundation
import Testing

@testable import PianismCore

/// How `TagIndex` reads parent links, whatever shape sync delivers (ADR 0013, the plan's "Sync shapes" table).
struct TagNestingTests {
    @Test("TAG-5: a tag inside another reads inside it, and as \"Parent › child\"; the parent reads as itself")
    func childReadsInsideItsParent() {
        // Given a skill inside a skill
        let index = TagIndex([tag("scales", name: "Scales"), tag("d-minor", name: "D minor", parent: "scales")])

        // When each is read
        let child = index["d-minor"]
        let parent = index["scales"]

        // Then the child sits inside the parent, which sits at the top level
        #expect(child.flatMap(index.parent(of:))?.id == "scales")
        #expect(parent.flatMap(index.parent(of:)) == nil)
        #expect(child.map(index.name(of:)) == "Scales › D minor")
        #expect(parent.map(index.name(of:)) == "Scales")
    }

    @Test("TAG-5, ADR 0013: a skill inside a built-in skill resolves, as the index holds the built-ins too")
    func builtInParent() {
        // Given the index as the app builds it, built-in skills first, and a skill inside Scales
        let scales = PianismCore.Tag(
            id: BuiltInSkill.scales.rawValue, kind: .skill, name: "Scales", isArchived: false, isReadOnly: true)
        let index = TagIndex([scales, tag("d-minor", name: "D minor", parent: BuiltInSkill.scales.rawValue)])

        // When the child is read
        let child = index["d-minor"]

        // Then it sits inside the built-in
        #expect(child.flatMap(index.parent(of:)) == scales)
        #expect(child.map(index.name(of:)) == "Scales › D minor")
    }

    @Test(
        "TAG-5, ADR 0013 rule 1 and 3: a parent not synced yet, or of the other kind, leaves the tag at the top level",
        arguments: ["not-synced-yet", "chopin"])
    func unknownOrOtherKindParent(parent: String) {
        // Given a skill whose stored parent is unknown here, or a piece
        let index = TagIndex([
            PianismCore.Tag(id: "chopin", kind: .piece, name: "Chopin", isArchived: false),
            tag("d-minor", name: "D minor", parent: parent),
        ])

        // When it's read
        let child = index["d-minor"]

        // Then it's at the top level, under its own name
        #expect(child.flatMap(index.parent(of:)) == nil)
        #expect(child.map(index.name(of:)) == "D minor")
    }

    @Test("TAG-5, ADR 0013 rule 4: a grandchild reads at the top level, and back inside once its parent moves out")
    func grandchildReadsAtTheTopLevel() {
        // Given C inside P, and D inside C, written on two devices
        let p = tag("p")
        let d = tag("d", parent: "c")
        let index = TagIndex([p, tag("c", parent: "p"), d])

        // When each is read, and again after C moves out to the top level
        let moved = TagIndex([p, tag("c"), d])

        // Then C is inside P and D at the top level, and once C is out, D is inside it with no write to D
        #expect(index["c"].flatMap(index.parent(of:))?.id == "p")
        #expect(index["d"].flatMap(index.parent(of:)) == nil)
        #expect(moved["d"].flatMap(moved.parent(of:))?.id == "c")
    }

    @Test("TAG-5, ADR 0013 rule 4: three devices nesting in a ring read as three top-level tags")
    func ringReadsAtTheTopLevel() {
        // Given T inside P, P inside G and G inside T
        let index = TagIndex([tag("t", parent: "p"), tag("p", parent: "g"), tag("g", parent: "t")])

        // When each is read
        let parents = ["t", "p", "g"].map { index[$0].flatMap(index.parent(of:)) }

        // Then each is at the top level, and reading them ends
        #expect(parents == [nil, nil, nil])
    }

    @Test(
        "TAG-5, ADR 0013 rule 5: two tags inside each other read with the one created first as the parent, in any order",
        arguments: [false, true])
    func mutualNestingOlderWins(reversed: Bool) {
        // Given A inside B and B inside A, A created first
        let older = tag("b", parent: "a", created: 1)
        let newer = tag("a", parent: "b", created: 2)
        let index = TagIndex(reversed ? [newer, older] : [older, newer])

        // When each is read
        let b = index["b"]
        let a = index["a"]

        // Then the older is the parent, at the top level
        #expect(a.flatMap(index.parent(of:))?.id == "b")
        #expect(b.flatMap(index.parent(of:)) == nil)
    }

    @Test("TAG-5, ADR 0013 rule 5: two tags inside each other, created at once, read with the lower ID as the parent")
    func mutualNestingTieByID() {
        // Given A inside B and B inside A, created at the same moment
        let index = TagIndex([tag("b", parent: "a"), tag("a", parent: "b")])

        // When each is read
        let parents = ["a", "b"].map { index[$0].flatMap(index.parent(of:))?.id }

        // Then A, the lower ID, is the parent
        #expect(parents == [nil, "a"])
    }

    @Test(
        "TAG-5, ADR 0013 rule 2: P, with a child, moved inside Q while Q is merged into P, stays at the top level with its child"
    )
    func parentMovedIntoATagMergedIntoIt() {
        // Given P inside Q on one device, Q merged into P on another, and C inside P
        let index = TagIndex([tag("p", parent: "q"), tag("q", mergedInto: "p"), tag("c", parent: "p")])

        // When each is read
        let p = index["p"]
        let c = index["c"]

        // Then P's link names itself, so P is at the top level and C is still inside it
        #expect(p.flatMap(index.parent(of:)) == nil)
        #expect(c.flatMap(index.parent(of:))?.id == "p")
    }

    @Test("TAG-5, ADR 0013 rule 2: a parent merged into its own child leaves the child at the top level")
    func parentMergedIntoItsChild() {
        // Given C inside P, and P merged into C
        let index = TagIndex([tag("p", mergedInto: "c"), tag("c", parent: "p")])

        // When both are read
        let c = index["c"]

        // Then P stands for C, and C is at the top level
        #expect(index["p"]?.id == "c")
        #expect(c.flatMap(index.parent(of:)) == nil)
        #expect(index.counted(for: ["p", "c"]).map(\.id) == ["c"])
    }

    @Test(
        "TAG-5, ADR 0013: a parent merged away passes its child to the kept tag, or to the top level if that's a child")
    func parentMergedAway() {
        // Given C inside P, and P merged into K, at the top level or inside G
        let topLevel = TagIndex([tag("p", mergedInto: "k"), tag("k"), tag("c", parent: "p")])
        let nested = TagIndex([tag("p", mergedInto: "k"), tag("k", parent: "g"), tag("g"), tag("c", parent: "p")])

        // When C is read
        let follows = topLevel["c"].flatMap(topLevel.parent(of:))
        let lifted = nested["c"].flatMap(nested.parent(of:))

        // Then C is inside K, and lifted to the top level when K is inside G
        #expect(follows?.id == "k")
        #expect(lifted == nil)
    }

    @Test("TAG-5, ADR 0013: a merged child stands for the tag it went into, with that tag's parent and name")
    func mergedChild() {
        // Given S inside P, and M, with a link of its own, merged into S
        let index = TagIndex([
            tag("p", name: "Scales"), tag("s", name: "D minor", parent: "p"), tag("x"),
            tag("m", name: "D-moll", parent: "x", mergedInto: "s"),
        ])

        // When M is read
        let merged = index["m"]

        // Then it reads as S, inside P
        #expect(merged.flatMap(index.parent(of:))?.id == "p")
        #expect(merged.map(index.name(of:)) == "Scales › D minor")
    }

    @Test(
        "TAG-5, ADR 0013: an archived parent reads unarchived while any child is unarchived, and archived again once none is"
    )
    func archivedParentWithLiveChild() {
        // Given P archived on one device, with children added on another, one archived and one not
        let p = tag("p", archived: true)
        let archived = tag("a", parent: "p", archived: true)
        let live = TagIndex([p, archived, tag("b", parent: "p")])
        let reversed = TagIndex([p, tag("b", parent: "p"), archived])

        // When the live child is archived too
        let none = TagIndex([p, archived, tag("b", parent: "p", archived: true)])

        // Then P reads unarchived while it has a live child, whichever comes first, and archived as stored after
        #expect(live["p"]?.isArchived == false)
        #expect(reversed["p"]?.isArchived == false)
        #expect(none["p"]?.isArchived == true)
    }

    @Test("TAG-5, ADR 0013: a tag merged away doesn't keep its archived parent live")
    func mergedChildDoesNotKeepParentLive() {
        // Given P archived, and M, inside P but merged into K at the top level, left unarchived by an older device
        let index = TagIndex([tag("p", archived: true), tag("k"), tag("m", parent: "p", mergedInto: "k")])

        // When P is read
        let p = index["p"]

        // Then nothing live is inside it, so it reads archived
        #expect(p?.isArchived == true)
    }

    @Test("TAG-5: a session counts toward its tags and their parents, each once, in order")
    func countedOnce() {
        // Given two children of one parent and a tag at the top level
        let index = TagIndex([tag("p"), tag("c1", parent: "p"), tag("c2", parent: "p"), tag("t")])

        // When a session tagged with both children, the parent and the other tag is counted
        let counted = index.counted(for: ["c1", "c2", "p", "t", "c1"])

        // Then the parent counts once
        #expect(counted.map(\.id) == ["c1", "c2", "p", "t"])
    }

    private func tag(
        _ id: String, kind: PianismCore.Tag.Kind = .skill, name: String? = nil, parent: String? = nil,
        mergedInto: String? = nil, archived: Bool = false, created: TimeInterval = 0
    ) -> PianismCore.Tag {
        PianismCore.Tag(
            id: id, kind: kind, name: name ?? id.uppercased(), isArchived: archived, mergedInto: mergedInto,
            parentID: parent, createdAt: Date(timeIntervalSince1970: created))
    }
}
