import Foundation

/// Where a piece's practice time goes (HIS-4): in all, over the last 30 days, and, from sessions a piano started in
/// those days, the time playing and the time paused. Pieces only, archived ones included, and a
/// merged piece as the piece it was merged into. A session with several pieces counts fully toward each (decided with
/// Ed, 2026-11-08).
public struct PieceStats: Sendable, Hashable, Identifiable {
    public let piece: Tag
    /// Practice time in all, as History's days add it up.
    public private(set) var total: TimeInterval = 0
    /// Practice time today and the 29 days before.
    public private(set) var recent: TimeInterval = 0
    /// Of the recent time, what sessions a piano started spent playing: all but their pauses, so a silence too short
    /// to pause one counts (MIDI-R2).
    public private(set) var playing: TimeInterval = 0
    /// The time those sessions spent paused, after a silence long enough to pause them (ADR 0009).
    public private(set) var paused: TimeInterval = 0

    public var id: Tag.ID { piece.id }
    /// Whether a piano started any of the recent sessions, so the split says something. Timer and added sessions
    /// have none, so playing and paused don't add up to the recent time unless every session was a piano's.
    public var hasPianoTime: Bool { playing + paused > 0 }

    /// Each piece practiced in `days`, the most practiced in all first. Each day counts its own part of a session, as
    /// History does, so the totals match it, and the 30 days are counted by date, for days of 23 and 25 hours.
    public static func of(
        _ days: [PracticeDay], in index: TagIndex, today: Date, calendar: Calendar
    ) -> [PieceStats] {
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: today)) ?? .distantPast
        var byPiece: [Tag.ID: PieceStats] = [:]
        for day in days {
            let isRecent = day.start >= since
            for session in day.sessions {
                let part = day.part(of: session)
                for piece in index.tags(for: session.tagIDs) where piece.kind == .piece {
                    var stats = byPiece[piece.id] ?? PieceStats(piece: piece)
                    stats.total += part.practiced
                    if isRecent {
                        stats.recent += part.practiced
                        if session.source == .midi {
                            stats.playing += part.practiced
                            let span = part.span.upperBound.timeIntervalSince(part.span.lowerBound)
                            stats.paused += max(0, span - part.practiced).rounded(.down)
                        }
                    }
                    byPiece[piece.id] = stats
                }
            }
        }
        return byPiece.values.sorted { first, second in
            guard first.total == second.total else { return first.total > second.total }
            // Two pieces can share a name, so the ID settles it, or their rows could swap between launches.
            let order = first.piece.name.localizedStandardCompare(second.piece.name)
            guard order == .orderedSame else { return order == .orderedAscending }
            return first.id < second.id  // mutate:ignore - two pieces never share an ID
        }
    }

    private init(piece: Tag) {
        self.piece = piece
    }
}
