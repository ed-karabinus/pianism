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

    @Test("TAG-1: built-in skills keep their IDs forever, because sessions store them")
    func builtInSkillIDsAreFixed() {
        #expect(
            BuiltInSkill.allCases.map(\.rawValue) == [
                "skill.scales", "skill.arpeggios", "skill.technique", "skill.sight-reading", "skill.repertoire",
                "skill.improvisation",
            ])
    }
}
