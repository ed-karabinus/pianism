import PianismCore
import SwiftUI

/// Time per piece and skill, a Pro feature (HIS-4): each piece's, or with the switch each skill's, time in all and over
/// the last 30 days, and, from sessions a piano started, the time playing and paused, as Practice words them (decided
/// with Ed, 2026-11-08; skills, behind a switch, 2026-11-09). It lists top-level tags, a parent's numbers including its
/// children's, and a parent's "N inside" row opens this screen for its children, titled with its name (D6, Ed's picks
/// 2026-11-10).
struct TagStatsView: View {
    /// Read only once the screen shows, and again as History changes, as a sync can arrive while it's open. Grouped by
    /// the tag each sits inside, `nil` for the top level, as ``HistoryModel/statsByParent(of:)`` gives them.
    let stats: (Tag.Kind) -> [Tag.ID?: [TagStats]]
    /// The tag whose children this lists, or `nil` for the top level.
    var parent: Tag?
    @State private var kind = Tag.Kind.piece

    var body: some View {
        let groups = stats(listed)
        let stats = groups[parent?.id] ?? []
        List {
            if !stats.isEmpty { rows(stats, groups: groups) }
        }
        .overlay {
            if stats.isEmpty { empty }
        }
        // iOS 26's soft edge fades past the bar onto the first header, which then failed the contrast audit; a hard
        // edge stops at the bar.
        .scrollEdgeEffectStyle(.hard, for: .top)
        // Above the list, not in it, so the empty state can't cover it. A bar, so the list blurs under it as it scrolls.
        // None inside a parent, whose kind is fixed.
        .safeAreaBar(edge: .top) {
            if parent == nil {
                Picker(selection: $kind) {
                    Text("Pieces", bundle: .module).tag(Tag.Kind.piece)
                    Text("Skills", bundle: .module).tag(Tag.Kind.skill)
                } label: {
                    Text("Pieces or skills", bundle: .module)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityID.tagStatsKind)
                .padding([.horizontal, .bottom])
            }
        }
        // The user's own name for the parent, as typed.
        .navigationTitle(parent.map { Text(verbatim: $0.name) } ?? Text("Time per piece and skill", bundle: .module))
    }

    /// The kind listed: the switch's, or inside a parent, the parent's.
    private var listed: Tag.Kind { parent?.kind ?? kind }

    @ViewBuilder private var empty: some View {
        switch listed {
        case .piece:
            ContentUnavailableView(
                LocalizedStringResource("No pieces yet", bundle: .module), systemImage: "music.note",
                description: Text("Tag a session with a piece to see its time here.", bundle: .module))
        case .skill:
            ContentUnavailableView(
                LocalizedStringResource("No skills yet", bundle: .module), systemImage: "music.note",
                description: Text("Tag a session with a skill to see its time here.", bundle: .module))
        }
    }

    @ViewBuilder private func rows(_ stats: [TagStats], groups: [Tag.ID?: [TagStats]]) -> some View {
        ForEach(stats) { tag in
            Section {
                TimedRow(title: Text("Total", bundle: .module), duration: tag.total)
                TimedRow(title: Text("Last 30 days", bundle: .module), duration: tag.recent)
                if tag.hasPianoTime {
                    TimedRow(title: Text("Playing", bundle: .module), duration: tag.playing)
                    TimedRow(title: Text("Paused", bundle: .module), duration: tag.paused)
                }
                // Only a top-level tag has a group, as tags nest one level (ADR 0013), so the screen this opens has
                // no such row.
                if let inside = groups[tag.id] {
                    NavigationLink {
                        TagStatsView(stats: self.stats, parent: tag.tag)
                    } label: {
                        Text(
                            "\(inside.count) inside", bundle: .module,
                            comment: "A row opening the pieces, or skills, practiced inside the one above")
                    }
                    .accessibilityIdentifier(AccessibilityID.tagStatsInside)
                }
            } header: {
                // The user's own name for it, as typed.
                Text(verbatim: tag.tag.name).textCase(nil)
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier(AccessibilityID.pieceStatsPiece)
            } footer: {
                if tag.hasPianoTime {
                    Text("From sessions your piano started in the last 30 days.", bundle: .module)
                        .foregroundStyle(.secondaryText)
                }
            }
        }
        Group {
            switch listed {
            case .piece: Text("A session with several pieces counts fully toward each.", bundle: .module)
            case .skill: Text("A session with several skills counts fully toward each.", bundle: .module)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondaryText)
        .listRowBackground(Color.clear)
    }
}

/// Two pieces inside "Études, Op. 10", one played on a piano, and a piece and a skill with nothing inside them.
private enum SampleStats {
    static let etudes = Tag(id: "etudes", kind: .piece, name: "Études, Op. 10", isArchived: false)

    static func of(_ kind: Tag.Kind) -> [Tag.ID?: [TagStats]] {
        let tags = TagIndex([
            etudes,
            Tag(id: "no-3", kind: .piece, name: "No. 3 in E major", isArchived: false, parentID: "etudes"),
            Tag(id: "no-12", kind: .piece, name: "No. 12 in C minor", isArchived: false, parentID: "etudes"),
            Tag(id: "bach", kind: .piece, name: "Prelude in C", isArchived: true),
            Tag(id: "scales", kind: .skill, name: "Scales: D minor", isArchived: false),
        ])
        let start = Date.now.addingTimeInterval(-86_400)
        var piano = PracticeSession(startedAt: start, source: .midi)
        try? piano.setTags(["no-3", "scales"])
        try? piano.pause(at: start + 1_200)
        try? piano.resume(at: start + 1_500)
        try? piano.stop(at: start + 2_400)
        var timed = PracticeSession(startedAt: start + 3_600)
        try? timed.setTags(["bach", "no-12"])
        try? timed.stop(at: start + 5_400)
        let days = PracticeDay.group([piano, timed], in: .current)
        let stats = TagStats.of(kind, in: days, tags: tags, today: .now, calendar: .current)
        return Dictionary(grouping: stats) { tags.parent(of: $0.tag)?.id }
    }
}

#Preview("Pieces") {
    NavigationStack { TagStatsView(stats: SampleStats.of) }
}

#Preview("Inside a piece, dark, AX5") {
    NavigationStack { TagStatsView(stats: SampleStats.of, parent: SampleStats.etudes) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("None, dark, AX5") {
    NavigationStack { TagStatsView { _ in [:] } }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
