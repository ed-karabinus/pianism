import Foundation
import PianismCore
import Testing

@Suite("EXP-1: the practice log as CSV")
struct PracticeLogCSVTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")
    private let start = Date(timeIntervalSince1970: 1_793_093_600)  // 2026-10-27 09:33:20 UTC

    @Test("EXP-1: one row per ended session, oldest first, after a byte order mark and the header, each ending in CRLF")
    func rowsInOrder() throws {
        var later = PracticeSession(startedAt: start + 3_600, timeZone: losAngeles)
        try later.stop(at: start + 3_600 + 600)
        var earlier = PracticeSession(startedAt: start, timeZone: losAngeles)
        try earlier.stop(at: start + 1_200)
        let running = PracticeSession(startedAt: start + 7_200)

        let text = try csv([later, running, earlier])

        #expect(PracticeLogCSV.file([], tags: TagIndex([])).prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        #expect(text.hasPrefix("\u{FEFF}started_at,ended_at,practiced_seconds,paused_seconds,source,tags,note\r\n"))
        #expect(
            lines(text) == [
                "started_at,ended_at,practiced_seconds,paused_seconds,source,tags,note",
                "2026-10-27T02:33:20-07:00,2026-10-27T02:53:20-07:00,1200,0,timer,,",
                "2026-10-27T03:33:20-07:00,2026-10-27T03:43:20-07:00,600,0,timer,,",
            ])
        #expect(text.hasSuffix("\r\n"))
        #expect(!text.dropLast(2).contains("\r\n\r\n"))
    }

    @Test("EXP-1: practiced and paused add up to the whole seconds the times show, however the fractions fall")
    func secondsAddUpToTheTimes() throws {
        var session = PracticeSession(startedAt: start + 0.9, timeZone: losAngeles)
        try session.stop(at: start + 1_800.2)

        let row = try fields(of: csv([session]))

        #expect(row[0...1] == ["2026-10-27T02:33:20-07:00", "2026-10-27T03:03:20-07:00"])
        #expect(row[2...3] == ["1799", "1"])
    }

    @Test("EXP-1: a session across the clocks going back ends at the zone's new offset")
    func acrossTheClocksGoingBack() throws {
        let fallBack = Date(timeIntervalSince1970: 1_793_523_600)  // 2026-11-01 09:00 UTC, 01:00 PST again
        var session = PracticeSession(startedAt: fallBack - 1_800, timeZone: losAngeles)
        try session.stop(at: fallBack + 1_800)

        let row = try fields(of: csv([session]))

        #expect(row[0...2] == ["2026-11-01T01:30:00-07:00", "2026-11-01T01:30:00-08:00", "3600"])
    }

    @Test("EXP-1: a session from before zones were kept is in UTC, marked Z")
    func noZoneIsUTC() throws {
        var session = PracticeSession(startedAt: start)
        try session.stop(at: start + 60)

        #expect(try fields(of: csv([session]))[0...1] == ["2026-10-27T09:33:20Z", "2026-10-27T09:34:20Z"])
    }

    @Test("EXP-1: times are whole seconds, practiced and paused add up to the span, and the source is named")
    func wholeSecondsAndPauses() throws {
        var session = PracticeSession(startedAt: start + 0.75, timeZone: losAngeles, source: .midi)
        try session.pause(at: start + 600.5)
        try session.resume(at: start + 900.25)
        try session.stop(at: start + 1_800.9)

        let row = try fields(of: csv([session]))

        #expect(row[0...1] == ["2026-10-27T02:33:20-07:00", "2026-10-27T03:03:20-07:00"])
        #expect(row[2...4] == ["1500", "300", "midi"])
    }

    @Test("EXP-1: tags by name in the session's order, a merged one as the tag it went into, once")
    func tagNames() throws {
        let index = TagIndex([
            Tag(id: "nocturne", kind: .piece, name: "Nocturne", isArchived: true),
            Tag(id: "old", kind: .piece, name: "Old name", isArchived: true, mergedInto: "nocturne"),
            Tag(id: BuiltInSkill.scales.rawValue, kind: .skill, name: "Scales", isArchived: false, isReadOnly: true),
        ])
        var session = PracticeSession(startedAt: start, timeZone: losAngeles)
        try session.setTags([BuiltInSkill.scales.rawValue, "old", "nocturne", "not synced yet"])
        try session.stop(at: start + 60)

        #expect(try fields(of: csv([session], tags: index))[5] == "Scales; Nocturne")
    }

    @Test(
        "EXP-1: text is as typed, quoted when it holds a comma, quote or line break, with quotes doubled",
        arguments: [
            ("- slow practice", "- slow practice"),
            ("=SUM(A1)", "=SUM(A1)"),
            ("left hand, then both", "\"left hand, then both\""),
            ("the \"Raindrop\" one", "\"the \"\"Raindrop\"\" one\""),
            ("bars 1–8\nthen 9", "\"bars 1–8\nthen 9\""),
            ("tempo 60\r\nthen 72", "\"tempo 60\r\nthen 72\""),
        ])
    func quoting(note: String, written: String) throws {
        var session = PracticeSession(startedAt: start, timeZone: losAngeles, source: .manual)
        try session.stop(at: start + 60)
        try session.editNote(note)

        let text = try csv([session])

        #expect(text.hasSuffix(",manual,," + written + "\r\n"))
    }

    @Test("EXP-1: a tag name is quoted like a note")
    func tagQuoting() throws {
        let index = TagIndex([Tag(id: "a", kind: .piece, name: "Prelude, Op. 28", isArchived: false)])
        var session = PracticeSession(startedAt: start, timeZone: losAngeles)
        try session.setTags(["a"])
        try session.stop(at: start + 60)

        #expect(try csv([session], tags: index).hasSuffix(",timer,\"Prelude, Op. 28\",\r\n"))
    }

    private func csv(_ sessions: [PracticeSession], tags: TagIndex = TagIndex([])) throws -> String {
        // Not String(data:encoding:), which drops the byte order mark.
        String(decoding: PracticeLogCSV.file(sessions, tags: tags), as: UTF8.self)
    }

    /// The lines after the byte order mark, for files with no line breaks inside a field.
    private func lines(_ text: String) -> [String] {
        Array(String(text.dropFirst()).components(separatedBy: "\r\n").dropLast())
    }

    /// The second line's fields, for a row with no commas inside a field.
    private func fields(of text: String) throws -> [String] {
        try #require(lines(text).dropFirst().first).components(separatedBy: ",")
    }
}
