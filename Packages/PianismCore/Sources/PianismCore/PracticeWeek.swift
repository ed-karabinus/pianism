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
            return byStart[day] ?? PracticeDay(start: day, in: calendar)
        }
    }

    /// The week's practice time with each top-level tag, longest first, ties by name as the tag picker sorts them, and
    /// then any untagged time. A session with several tags counts in full toward each, a merged tag as the tag it was
    /// merged into, and a tag inside another toward that parent, once however many of its children the session has
    /// (D7). A parent brings the tags inside it with any time this week, each with its own, sorted the same way. Each
    /// day counts its own part of a session, so one across midnight isn't counted twice, and one across the week's
    /// edge counts only the minutes inside it.
    public func timeByTag(in index: TagIndex) -> [TagTime] {
        var byTag: [Tag.ID: TagTime] = [:]
        var byChild: [Tag.ID: TagTime] = [:]
        var untagged = TagTime(tag: nil, time: 0)
        for day in days {
            for session in day.sessions {
                let time = day.part(of: session).practiced
                let tags = index.counted(for: session.tagIDs)
                if tags.isEmpty { untagged.time += time }
                for tag in tags {
                    if index.parent(of: tag) == nil {
                        byTag[tag.id, default: TagTime(tag: tag, time: 0)].time += time
                    } else {
                        byChild[tag.id, default: TagTime(tag: tag, time: 0)].time += time
                    }
                }
            }
        }
        // A session counts toward a child's parent too, so every child's parent has a time here.
        for child in Self.sorted(byChild.values) {
            if let tag = child.tag, let parent = index.parent(of: tag) { byTag[parent.id]?.inside.append(child) }
        }
        return Self.sorted(byTag.values) + (untagged.time > 0 ? [untagged] : [])
    }

    /// Longest first, ties by name as the tag picker sorts them, then by ID.
    private static func sorted(_ times: some Sequence<TagTime>) -> [TagTime] {
        times.sorted { first, second in
            guard first.time == second.time else {
                return first.time > second.time  // mutate:ignore - the times differ here
            }
            // A piece and a skill can share a name, so the ID settles it, or their rows could swap between launches.
            let order = (first.tag?.name ?? "").localizedStandardCompare(second.tag?.name ?? "")
            guard order == .orderedSame else { return order == .orderedAscending }
            return first.id ?? "" < second.id ?? ""  // mutate:ignore - two tags never share an ID
        }
    }

    /// Practice time with a tag, or untagged with `tag` nil (HIS-2).
    public struct TagTime: Sendable, Hashable, Identifiable {
        public let tag: Tag?
        public var time: TimeInterval
        /// The time with each tag inside this one that has any, longest first (TAG-5).
        public var inside: [TagTime] = []
        public var id: Tag.ID? { tag?.id }
    }
}
