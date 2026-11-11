import Foundation

/// Where a piece's or a skill's practice time goes (HIS-4): in all, over the last 30 days, and, from sessions a piano
/// started in those days, the time playing and the time paused. Archived tags included, and a merged tag as the tag it
/// was merged into. A session with several pieces or skills counts fully toward each (decided with Ed, 2026-11-08;
/// skills added 2026-11-09).
public struct TagStats: Sendable, Hashable, Identifiable {
    public let tag: Tag
    /// Practice time in all, as History's days add it up.
    public private(set) var total: TimeInterval = 0
    /// Practice time today and the 29 days before.
    public private(set) var recent: TimeInterval = 0
    /// Of the recent time, what sessions a piano started spent playing: all but their pauses, so a silence too short
    /// to pause one counts (MIDI-R2).
    public private(set) var playing: TimeInterval = 0
    /// The time those sessions spent paused, after a silence long enough to pause them (ADR 0009).
    public private(set) var paused: TimeInterval = 0

    public var id: Tag.ID { tag.id }
    /// Whether a piano started any of the recent sessions, so the split says something. Timer and added sessions
    /// have none, so playing and paused don't add up to the recent time unless every session was a piano's.
    public var hasPianoTime: Bool { playing + paused > 0 }

    /// Each piece, or each skill, practiced in `days`, the most practiced in all first. Each day counts its own part of
    /// a session, as History does, so the totals match it, and the 30 days are counted by date, for days of 23 and 25
    /// hours.
    public static func of(
        _ kind: Tag.Kind, in days: [PracticeDay], tags index: TagIndex, today: Date, calendar: Calendar
    ) -> [TagStats] {
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: today)) ?? .distantPast
        var byTag: [Tag.ID: TagStats] = [:]
        for day in days {
            let isRecent = day.start >= since
            for session in day.sessions {
                let part = day.part(of: session)
                for tag in index.tags(for: session.tagIDs) where tag.kind == kind {
                    var stats = byTag[tag.id] ?? TagStats(tag: tag)
                    stats.total += part.practiced
                    if isRecent {
                        stats.recent += part.practiced
                        if session.source == .midi {
                            stats.playing += part.practiced
                            let span = part.span.upperBound.timeIntervalSince(part.span.lowerBound)
                            stats.paused += max(0, span - part.practiced).rounded(.down)
                        }
                    }
                    byTag[tag.id] = stats
                }
            }
        }
        return byTag.values.sorted { first, second in
            // Past the guard the totals differ, so `>=` would sort them the same.
            guard first.total == second.total else { return first.total > second.total }  // mutate:ignore - see above
            // Two tags can share a name, so the ID settles it, or their rows could swap between launches.
            let order = first.tag.name.localizedStandardCompare(second.tag.name)
            guard order == .orderedSame else { return order == .orderedAscending }
            return first.id < second.id  // mutate:ignore - two tags never share an ID
        }
    }

    private init(tag: Tag) {
        self.tag = tag
    }
}
