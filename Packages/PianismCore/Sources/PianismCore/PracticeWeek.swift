import Foundation

/// One week of practice at a glance (HIS-2): its seven days, oldest first, each with its total, and the week's
/// total.
public struct PracticeWeek: Sendable {
    /// The week's seven days, oldest first, including days without practice.
    public let days: [PracticeDay]
    /// Practice time of all the week's sessions, excluding pauses (SES-2).
    public var total: TimeInterval { days.reduce(0) { $0 + $1.total } }

    /// The week holding `date`, on the calendar's first weekday, from `days` as ``PracticeDay/group(_:in:)`` makes
    /// them. Days are found by date, not by counting hours, so a week with a daylight-saving change still has seven.
    public init(containing date: Date, days: [PracticeDay], in calendar: Calendar) {
        // Can't fail: every date falls in some week.
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let byStart = Dictionary(days.map { ($0.start, $0) }) { first, _ in first }
        self.days = (0..<7).map { offset in
            // Where the clocks change at midnight, as in Santiago, a day starts at 1:00, as `group` keys it.
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start) ?? start)
            return byStart[day] ?? PracticeDay(start: day, sessions: [], total: 0)
        }
    }

    /// The week's practice time with each tag, longest first, ties by name as the tag picker sorts them, and then any
    /// untagged time. A session with several tags counts in full toward each, and a merged tag as the tag it was
    /// merged into.
    public func timeByTag(in index: TagIndex) -> [TagTime] {
        var byTag: [Tag.ID: TagTime] = [:]
        var untagged = TagTime(tag: nil, time: 0)
        for session in days.flatMap(\.sessions) {
            let time = session.elapsed(at: .distantPast)
            let tags = index.tags(for: session.tagIDs)
            if tags.isEmpty { untagged.time += time }
            for tag in tags { byTag[tag.id, default: TagTime(tag: tag, time: 0)].time += time }
        }
        let tagged = byTag.values.sorted { first, second in
            guard first.time == second.time else { return first.time > second.time }
            // A piece and a skill can share a name, so the ID settles it, or their rows could swap between launches.
            let order = (first.tag?.name ?? "").localizedStandardCompare(second.tag?.name ?? "")
            return order == .orderedSame ? first.id ?? "" < second.id ?? "" : order == .orderedAscending
        }
        return tagged + (untagged.time > 0 ? [untagged] : [])
    }

    /// Practice time with a tag, or untagged with `tag` nil (HIS-2).
    public struct TagTime: Sendable, Hashable, Identifiable {
        public let tag: Tag?
        public var time: TimeInterval
        public var id: Tag.ID? { tag?.id }
    }
}
