import Foundation
import PianismCore
import Testing

struct TagTests {
    let tags = [
        Tag(id: "1", kind: .piece, name: "Für Elise", isArchived: true),
        Tag(id: "2", kind: .skill, name: "Pedalling", isArchived: false),
    ]

    @Test(
        "TAG-1: adding a name already in use, ignoring case, accents and spaces, finds that tag, archived too",
        arguments: ["Für Elise", "fur elise", "  FÜR ELISE ", "Ｆür Elise"])
    func findsExistingName(_ name: String) {
        #expect(Tag.existing(named: name, kind: .piece, in: tags) == tags[0])
    }

    @Test("TAG-1: a piece and a skill may share a name, and a different name is new")
    func otherKindOrNameIsNew() {
        #expect(Tag.existing(named: "Pedalling", kind: .piece, in: tags) == nil)
        #expect(Tag.existing(named: "Für Elise II", kind: .piece, in: tags) == nil)
    }

    @Test("TAG-1: when two tags share a name, the unarchived one is offered, wherever it is", arguments: [false, true])
    func prefersUnarchived(reversed: Bool) {
        let current = Tag(id: "3", kind: .piece, name: "Fur Elise", isArchived: false)
        let both = reversed ? [current, tags[0]] : [tags[0], current]

        #expect(Tag.existing(named: "Für Elise", kind: .piece, in: both) == current)
    }

    @Test("TAG-3: a piece loaded with its composer and target tempo keeps them")
    func keepsDetails() {
        let piece = Tag(id: "4", kind: .piece, name: "Ballade", isArchived: false, composer: "Chopin", targetTempo: 72)

        #expect(piece.composer == "Chopin" && piece.targetTempo == 72)
    }

    @Test("TAG-1: built-in skills keep their IDs forever, because sessions store them")
    func builtInSkillIDsAreFixed() {
        #expect(
            BuiltInSkill.allCases.map(\.rawValue) == [
                "skill.scales", "skill.arpeggios", "skill.technique", "skill.sight-reading", "skill.repertoire",
                "skill.improvisation",
            ])
    }
}

struct TagIndexTests {
    let start = Date(timeIntervalSince1970: 1_798_761_600)

    @Test("ADR 0004: a merged tag stands for the tag it was merged into, to the end of a chain")
    func followsMerges() {
        let kept = tag("c")
        let index = TagIndex([tag("a", mergedInto: "b"), tag("b", mergedInto: "c"), kept])

        #expect(index["a"] == kept)
        #expect(index["b"] == kept)
        #expect(index["c"] == kept)
    }

    @Test(
        "ADR 0004: tags merged into each other stand for the one created first, whichever is read",
        arguments: [false, true])
    func cycleKeepsEarliestCreated(reversed: Bool) {
        // a → b → c → a, from three devices merging at once. b was created first.
        let cycle = [
            tag("a", mergedInto: "b", createdAfter: 20), tag("b", mergedInto: "c", createdAfter: 10),
            tag("c", mergedInto: "a", createdAfter: 30),
        ]
        let index = TagIndex(reversed ? cycle.reversed() : cycle)

        #expect(["a", "b", "c"].map { index[$0]?.id } == ["b", "b", "b"])
    }

    @Test("ADR 0004: in a cycle of tags created at once, the lowest ID wins")
    func cycleTieBreaksByID() {
        let index = TagIndex([tag("b", mergedInto: "a"), tag("a", mergedInto: "b")])

        #expect(index["a"]?.id == "a")
        #expect(index["b"]?.id == "a")
    }

    @Test("ADR 0004: a tag that leads into a cycle stands for the cycle's survivor")
    func chainIntoCycle() {
        let index = TagIndex([
            tag("z", mergedInto: "b", createdAfter: 0), tag("b", mergedInto: "c", createdAfter: 20),
            tag("c", mergedInto: "b", createdAfter: 10),
        ])

        #expect(index["z"]?.id == "c")
    }

    @Test("ADR 0004: a tag merged into one that hasn't synced yet, or into itself, stands for itself")
    func unknownTargetStandsForItself() {
        let waiting = tag("a", mergedInto: "not-synced")
        let selfMerged = tag("s", mergedInto: "s")
        let index = TagIndex([waiting, selfMerged])

        #expect(index["a"] == waiting)
        #expect(index["s"] == selfMerged)
        #expect(index["not-synced"] == nil)
    }

    @Test("TAG-2: a session's tags read once each, in order, leaving out ones not known yet")
    func sessionTags() {
        let kept = tag("b")
        let other = tag("c")
        let index = TagIndex([tag("a", mergedInto: "b"), kept, other])

        #expect(index.tags(for: ["c", "a", "unknown", "b"]) == [other, kept])
        #expect(index.tags(for: ["unknown"]).isEmpty)
    }

    // `PianismCore.Tag` in types, since Swift Testing has a `Tag` too.
    private func tag(_ id: String, mergedInto: String? = nil, createdAfter seconds: TimeInterval = 0) -> PianismCore.Tag
    {
        Tag(
            id: id, kind: .piece, name: id, isArchived: mergedInto != nil, mergedInto: mergedInto,
            createdAt: start + seconds)
    }
}
