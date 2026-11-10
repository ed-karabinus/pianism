import Foundation
import Testing

@testable import PianismCore

struct TagStatsTests {
    let chopin = PianismCore.Tag(id: "chopin", kind: .piece, name: "Chopin", isArchived: false)
    let bach = PianismCore.Tag(id: "bach", kind: .piece, name: "Bach", isArchived: true)
    let scales = PianismCore.Tag(id: "scales", kind: .skill, name: "Scales", isArchived: false)

    @Test(
        "HIS-4: the totals add History's day parts, so a session across midnight counts once, and the 30 days are today and the 29 before, by date"
    )
    func totalsMatchHistory() throws {
        let calendar = try losAngeles()
        // 1 November 2026 is 25 hours long there, as the clocks go back, and the first of the 30 days to 30 November.
        let sessions = [
            try session(at: date(2026, 11, 1, 10, 0, in: calendar), minutes: 30, tags: ["chopin"]),
            try session(at: date(2026, 10, 31, 23, 30, in: calendar), minutes: 60, tags: ["chopin"]),
            try session(at: date(2026, 10, 15, 8, 0, in: calendar), minutes: 20, tags: ["chopin"]),
        ]

        let stats = TagStats.of(
            .piece, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([chopin]),
            today: try date(2026, 11, 30, 12, 0, in: calendar), calendar: calendar)

        #expect(stats.map(\.tag.id) == ["chopin"])
        let piece = try #require(stats.first)
        #expect(piece.total == 110 * 60)
        #expect(piece.recent == 60 * 60, "The 30 days hold 1 November's 30 minutes and 30 more after midnight")
    }

    @Test("HIS-4: a merged piece counts as the piece it was merged into, once even in a session tagged with both")
    func mergedPiecesCountOnce() throws {
        let calendar = try losAngeles()
        let merged = PianismCore.Tag(
            id: "nocturne", kind: .piece, name: "Nocturne", isArchived: false, mergedInto: "chopin")
        let start = try date(2026, 11, 20, 18, 0, in: calendar)
        let sessions = [
            try session(at: start, minutes: 10, tags: ["chopin", "nocturne"]),
            try session(at: start + 3_600, minutes: 5, tags: ["nocturne"]),
        ]

        let stats = TagStats.of(
            .piece, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([chopin, merged]), today: start,
            calendar: calendar)

        #expect(stats.map(\.tag.id) == ["chopin"])
        #expect(try #require(stats.first).total == 15 * 60)
    }

    @Test(
        "HIS-4: a session with several pieces counts fully toward each, archived ones included, skills get no row, and the most practiced comes first"
    )
    func severalPiecesCountFully() throws {
        let calendar = try losAngeles()
        let start = try date(2026, 11, 20, 18, 0, in: calendar)
        let sessions = [
            try session(at: start, minutes: 30, tags: ["chopin", "bach", "scales"]),
            try session(at: start + 3_600, minutes: 10, tags: ["chopin"]),
        ]

        let stats = TagStats.of(
            .piece, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([chopin, bach, scales]), today: start,
            calendar: calendar)

        // Typed apart, as CI's older compiler times out inferring the literal inside the comparison.
        let totals: [TimeInterval] = [40 * 60, 30 * 60]
        #expect(stats.map(\.tag.id) == ["chopin", "bach"])
        #expect(stats.map(\.total) == totals)
    }

    @Test("HIS-4: two pieces with the same time are in name order")
    func tiesGoByName() throws {
        let calendar = try losAngeles()
        let start = try date(2026, 11, 20, 18, 0, in: calendar)
        // IDs in the other order, so only the names can put them in this one.
        let first = PianismCore.Tag(id: "2", kind: .piece, name: "Bach", isArchived: false)
        let second = PianismCore.Tag(id: "1", kind: .piece, name: "Chopin", isArchived: false)
        let sessions = [try session(at: start, minutes: 30, tags: ["1", "2"])]

        let stats = TagStats.of(
            .piece, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([first, second]), today: start,
            calendar: calendar)

        #expect(stats.map(\.tag.name) == ["Bach", "Chopin"])
    }

    @Test(
        "HIS-4: playing and paused time come from piano sessions in the 30 days, paused being the pauses; a timer session adds to neither"
    )
    func theSplitComesFromPianoSessions() throws {
        let calendar = try losAngeles()
        let today = try date(2026, 11, 30, 12, 0, in: calendar)
        let start = try date(2026, 11, 29, 18, 0, in: calendar)
        var piano = PracticeSession(startedAt: start, source: .midi)
        try piano.setTags(["chopin"])
        try piano.pause(at: start + 20 * 60)
        try piano.resume(at: start + 25 * 60)
        try piano.stop(at: start + 40 * 60)
        var old = PracticeSession(startedAt: start - 40 * 86_400, source: .midi)
        try old.setTags(["chopin"])
        try old.stop(at: old.startedAt + 15 * 60)
        let sessions = [
            piano, old,
            try session(at: start + 3_600, minutes: 10, tags: ["chopin"]),
            try session(at: start, minutes: 10, tags: ["bach"]),
        ]

        let stats = TagStats.of(
            .piece, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([chopin, bach]), today: today,
            calendar: calendar)

        let chopinStats = try #require(stats.first { $0.tag.id == "chopin" })
        #expect(chopinStats.recent == 45 * 60)
        #expect(chopinStats.playing == 35 * 60)
        #expect(chopinStats.paused == 5 * 60)
        #expect(chopinStats.hasPianoTime)
        let bachStats = try #require(stats.first { $0.tag.id == "bach" })
        #expect(!bachStats.hasPianoTime)
    }

    @Test("HIS-4: a piano session from before the 30 days splits only its part inside them")
    func theSplitKeepsToTheDays() throws {
        let calendar = try losAngeles()
        let today = try date(2026, 11, 30, 12, 0, in: calendar)
        let start = try date(2026, 10, 31, 23, 40, in: calendar)
        var piano = PracticeSession(startedAt: start, source: .midi)
        try piano.setTags(["chopin"])
        try piano.pause(at: start + 5 * 60)
        try piano.resume(at: start + 15 * 60)
        try piano.stop(at: start + 30 * 60)

        let stats = TagStats.of(
            .piece, in: PracticeDay.group([piano], in: calendar), tags: TagIndex([chopin]), today: today,
            calendar: calendar)

        let chopinStats = try #require(stats.first)
        #expect(chopinStats.total == 20 * 60)
        #expect(chopinStats.recent == 10 * 60)
        #expect(chopinStats.playing == 10 * 60)
        #expect(chopinStats.paused == 0)
    }

    @Test(
        "HIS-4: skills get their own stats, without pieces, a session with several counting fully toward each, the way pieces do"
    )
    func skillsCountLikePieces() throws {
        // Given a skill of the user's own beside a built-in one, as for scales in one key
        let calendar = try losAngeles()
        let start = try date(2026, 11, 20, 18, 0, in: calendar)
        let dMinor = PianismCore.Tag(id: "d-minor", kind: .skill, name: "Scales: D minor", isArchived: false)
        let sessions = [
            try session(at: start, minutes: 20, tags: ["chopin", "scales", "d-minor"]),
            try session(at: start + 3_600, minutes: 10, tags: ["scales"]),
        ]

        // When the skills' stats are counted
        let stats = TagStats.of(
            .skill, in: PracticeDay.group(sessions, in: calendar), tags: TagIndex([chopin, scales, dMinor]),
            today: start, calendar: calendar)

        // Then each skill has its own time, and the piece has none here
        let times: [TimeInterval] = [30 * 60, 20 * 60]
        #expect(stats.map(\.tag.id) == ["scales", "d-minor"])
        #expect(stats.map(\.total) == times)
        #expect(stats.map(\.recent) == times)
    }

    private func losAngeles() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar)
        throws -> Date
    {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func session(at start: Date, minutes: Double, tags: [PianismCore.Tag.ID]) throws -> PracticeSession {
        var session = PracticeSession(startedAt: start)
        try session.setTags(tags)
        try session.stop(at: start + minutes * 60)
        return session
    }
}
