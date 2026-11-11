import Foundation

/// Every session as a CSV file the user can take anywhere (EXP-1): one row per session, oldest first, with its times
/// in the zone it was played in, whole seconds, how it was recorded, its tags by name ("Scales › D minor" for one
/// inside another, D5) and its note, as typed (decided with Ed, 2026-11-08). RFC 4180, with CRLF line ends and a byte
/// order mark, so spreadsheet apps read the accents.
public enum PracticeLogCSV {
    private static let header = [
        "started_at", "ended_at", "practiced_seconds", "paused_seconds", "source", "tags", "note",
    ]

    /// The file for `sessions`, leaving out any not ended yet; `index` names their tags, merged ones as the tag they
    /// were merged into.
    public static func file(_ sessions: [PracticeSession], tags index: TagIndex) -> Data {
        let ended = sessions.compactMap { session in session.endedAt.map { (session, $0) } }
            // Every session's ID differs, so two rows never compare equal, and `<=` would sort them the same.
            .sorted {
                ($0.0.startedAt, $0.0.id.uuidString) < ($1.0.startedAt, $1.0.id.uuidString)  // mutate:ignore - no ties
            }
        let rows = [header] + ended.map { session, end in row(session, end: end, tags: index) }
        let text = rows.map { $0.map(field).joined(separator: ",") + "\r\n" }.joined()
        return Data(("\u{FEFF}" + text).utf8)
    }

    private static func row(_ session: PracticeSession, end: Date, tags index: TagIndex) -> [String] {
        let zone = session.timeZone ?? .gmt
        let practiced = Int(session.practiced(before: end))
        // From the whole seconds the two times show, so the columns add up to what they say.
        let span = Int(
            end.timeIntervalSince1970.rounded(.down) - session.startedAt.timeIntervalSince1970.rounded(.down))
        let time = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: zone)
        return [
            session.startedAt.formatted(time),
            end.formatted(time),
            String(practiced),
            String(max(0, span - practiced)),
            session.source.rawValue,
            index.tags(for: session.tagIDs).map(index.name(of:)).joined(separator: "; "),
            session.note,
        ]
    }

    /// Quoted only when it has to be, with its quotes doubled (RFC 4180), and otherwise as typed: no `'` before a
    /// leading `=` or `-`, as the file is the user's own words, read by the person who wrote them (N3).
    private static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
