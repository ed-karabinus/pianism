import Foundation
import Testing

@testable import PianismCore

struct PieceStatsTests {
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

        let stats = PieceStats.of(
            PracticeDay.group(sessions, in: calendar), in: TagIndex([chopin]),
            today: try date(2026, 11, 30, 12, 0, in: calendar), calendar: calendar)

        #expect(stats.map(\.piece.id) == ["chopin"])
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

        let stats = PieceStats.of(
            PracticeDay.group(sessions, in: calendar), in: TagIndex([chopin, merged]), today: start, calendar: calendar)

        #expect(stats.map(\.piece.id) == ["chopin"])
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

        let stats = PieceStats.of(
            PracticeDay.group(sessions, in: calendar), in: TagIndex([chopin, bach, scales]), today: start,
            calendar: calendar)

        #expect(stats.map(\.piece.id) == ["chopin", "bach"])
        #expect(stats.map(\.total) == [40 * 60, 30 * 60])
    }

    @Test("HIS-4: two pieces with the same time are in name order")
    func tiesGoByName() throws {
        let calendar = try losAngeles()
        let start = try date(2026, 11, 20, 18, 0, in: calendar)
        // IDs in the other order, so only the names can put them in this one.
        let first = PianismCore.Tag(id: "2", kind: .piece, name: "Bach", isArchived: false)
        let second = PianismCore.Tag(id: "1", kind: .piece, name: "Chopin", isArchived: false)
        let sessions = [try session(at: start, minutes: 30, tags: ["1", "2"])]

        let stats = PieceStats.of(
            PracticeDay.group(sessions, in: calendar), in: TagIndex([first, second]), today: start, calendar: calendar)

        #expect(stats.map(\.piece.name) == ["Bach", "Chopin"])
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

        let stats = PieceStats.of(
            PracticeDay.group(sessions, in: calendar), in: TagIndex([chopin, bach]), today: today, calendar: calendar)

        let chopinStats = try #require(stats.first { $0.piece.id == "chopin" })
        #expect(chopinStats.recent == 45 * 60)
        #expect(chopinStats.playing == 35 * 60)
        #expect(chopinStats.paused == 5 * 60)
        #expect(chopinStats.hasPianoTime)
        let bachStats = try #require(stats.first { $0.piece.id == "bach" })
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

        let stats = PieceStats.of(
            PracticeDay.group([piano], in: calendar), in: TagIndex([chopin]), today: today, calendar: calendar)

        let chopinStats = try #require(stats.first)
        #expect(chopinStats.total == 20 * 60)
        #expect(chopinStats.recent == 10 * 60)
        #expect(chopinStats.playing == 10 * 60)
        #expect(chopinStats.paused == 0)
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
