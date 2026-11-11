import PianismCore
import SwiftUI

/// Time per piece and skill, a Pro feature (HIS-4): each piece's, or with the switch each skill's, time in all and over
/// the last 30 days, and, from sessions a piano started, the time playing and paused, as Practice words them (decided
/// with Ed, 2026-11-08; skills, behind a switch, 2026-11-09).
struct TagStatsView: View {
    /// Read only once the screen shows, and again as History changes, as a sync can arrive while it's open.
    let stats: (Tag.Kind) -> [TagStats]
    @State private var kind = Tag.Kind.piece

    var body: some View {
        let stats = stats(kind)
        List {
            if !stats.isEmpty { rows(stats) }
        }
        .overlay {
            if stats.isEmpty { empty }
        }
        // iOS 26's soft edge fades past the bar onto the first header, which then failed the contrast audit; a hard
        // edge stops at the bar.
        .scrollEdgeEffectStyle(.hard, for: .top)
        // Above the list, not in it, so the empty state can't cover it. A bar, so the list blurs under it as it scrolls.
        .safeAreaBar(edge: .top) {
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
        .navigationTitle(Text("Time per piece and skill", bundle: .module))
        // In the bar, as on iPad: an iPhone's large title sat under the hard top edge above, which blurred it.
        .toolbarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var empty: some View {
        switch kind {
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

    @ViewBuilder private func rows(_ stats: [TagStats]) -> some View {
        ForEach(stats) { tag in
            Section {
                TimedRow(title: Text("Total", bundle: .module), duration: tag.total)
                TimedRow(title: Text("Last 30 days", bundle: .module), duration: tag.recent)
                if tag.hasPianoTime {
                    TimedRow(title: Text("Playing", bundle: .module), duration: tag.playing)
                    TimedRow(title: Text("Paused", bundle: .module), duration: tag.paused)
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
            switch kind {
            case .piece: Text("A session with several pieces counts fully toward each.", bundle: .module)
            case .skill: Text("A session with several skills counts fully toward each.", bundle: .module)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondaryText)
        .listRowBackground(Color.clear)
    }
}

#Preview("Pieces") {
    let chopin = Tag(id: "chopin", kind: .piece, name: "Nocturne in E-flat", isArchived: false)
    let bach = Tag(id: "bach", kind: .piece, name: "Prelude in C", isArchived: true)
    let scales = Tag(id: "scales", kind: .skill, name: "Scales: D minor", isArchived: false)
    let start = Date.now.addingTimeInterval(-86_400)
    var piano = PracticeSession(startedAt: start, source: .midi)
    try? piano.setTags(["chopin", "scales"])
    try? piano.pause(at: start + 1_200)
    try? piano.resume(at: start + 1_500)
    try? piano.stop(at: start + 2_400)
    var timed = PracticeSession(startedAt: start + 3_600)
    try? timed.setTags(["bach", "chopin"])
    try? timed.stop(at: start + 5_400)
    let days = PracticeDay.group([piano, timed], in: .current)
    let tags = TagIndex([chopin, bach, scales])
    return NavigationStack {
        TagStatsView { TagStats.of($0, in: days, tags: tags, today: .now, calendar: .current) }
    }
}

#Preview("None, dark, AX5") {
    NavigationStack { TagStatsView { _ in [] } }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
