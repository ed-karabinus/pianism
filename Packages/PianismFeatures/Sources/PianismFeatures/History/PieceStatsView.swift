import PianismCore
import SwiftUI

/// Time per piece, a Pro feature (HIS-4): each piece's time in all and over the last 30 days, and, from sessions a
/// piano started, the time playing and paused, as Practice words them (decided with Ed, 2026-11-08).
struct PieceStatsView: View {
    /// Read only once the screen shows, and again as History changes, as a sync can arrive while it's open.
    let stats: () -> [PieceStats]

    var body: some View {
        let stats = stats()
        Group {
            if stats.isEmpty {
                ContentUnavailableView(
                    LocalizedStringResource("No pieces yet", bundle: .module), systemImage: "music.note",
                    description: Text("Tag a session with a piece to see its time here.", bundle: .module))
            } else {
                list(stats)
            }
        }
        .navigationTitle(Text("Time per piece", bundle: .module))
    }

    private func list(_ stats: [PieceStats]) -> some View {
        List {
            ForEach(stats) { piece in
                Section {
                    TimedRow(title: Text("Total", bundle: .module), duration: piece.total)
                    TimedRow(title: Text("Last 30 days", bundle: .module), duration: piece.recent)
                    if piece.hasPianoTime {
                        TimedRow(title: Text("Playing", bundle: .module), duration: piece.playing)
                        TimedRow(title: Text("Paused", bundle: .module), duration: piece.paused)
                    }
                } header: {
                    // The user's own name for it, as typed.
                    Text(verbatim: piece.piece.name).textCase(nil)
                        .accessibilityIdentifier(AccessibilityID.pieceStatsPiece)
                } footer: {
                    if piece.hasPianoTime {
                        Text("From sessions your piano started in the last 30 days.", bundle: .module)
                    }
                }
            }
            Text("A session with several pieces counts fully toward each.", bundle: .module)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
    }
}

#Preview("Pieces") {
    let chopin = Tag(id: "chopin", kind: .piece, name: "Nocturne in E-flat", isArchived: false)
    let bach = Tag(id: "bach", kind: .piece, name: "Prelude in C", isArchived: true)
    let start = Date.now.addingTimeInterval(-86_400)
    var piano = PracticeSession(startedAt: start, source: .midi)
    try? piano.setTags(["chopin"])
    try? piano.pause(at: start + 1_200)
    try? piano.resume(at: start + 1_500)
    try? piano.stop(at: start + 2_400)
    var timed = PracticeSession(startedAt: start + 3_600)
    try? timed.setTags(["bach", "chopin"])
    try? timed.stop(at: start + 5_400)
    let days = PracticeDay.group([piano, timed], in: .current)
    return NavigationStack {
        PieceStatsView { PieceStats.of(days, in: TagIndex([chopin, bach]), today: .now, calendar: .current) }
    }
}

#Preview("None, dark, AX5") {
    NavigationStack { PieceStatsView { [] } }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
