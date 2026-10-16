import Foundation
import PianismCore
import Testing

/// Sessions as builds have written them to devices: in the running-session file (ADR 0003) and in the
/// outbox (ADR 0007). Every build must read every sample, or an update loses the session that was
/// running, and every waiting one. Never edit a sample; when the format changes, add one.
struct SessionFileFormatTests {
    let id = UUID(uuidString: "3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90")
    let vienna = TimeZone(identifier: "Europe/Vienna")

    @Test("ADR 0003: a paused session, as written since time zones were recorded, still reads")
    func pausedSessionReads() throws {
        let written =
            #"{"pauses":[{"start":820454700.5,"end":820454760.75},{"start":820455000.125}],"#
            + #""startedAt":820454400.25,"id":"3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90","#
            + #""timeZone":{"identifier":"Europe\/Vienna"}}"#
        var expected = PracticeSession(id: try #require(id), startedAt: date(820_454_400.25), timeZone: vienna)
        try expected.pause(at: date(820_454_700.5))
        try expected.resume(at: date(820_454_760.75))
        try expected.pause(at: date(820_455_000.125))

        #expect(try JSONDecoder().decode(PracticeSession.self, from: Data(written.utf8)) == expected)
    }

    @Test("ADR 0003, 0007: an ended session, as written since time zones were recorded, still reads")
    func endedSessionReads() throws {
        let written =
            #"{"pauses":[{"start":820454700.5,"end":820454760.75}],"endedAt":820456200.875,"#
            + #""startedAt":820454400.25,"id":"3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90","#
            + #""timeZone":{"identifier":"Europe\/Vienna"}}"#
        var expected = PracticeSession(id: try #require(id), startedAt: date(820_454_400.25), timeZone: vienna)
        try expected.pause(at: date(820_454_700.5))
        try expected.resume(at: date(820_454_760.75))
        try expected.stop(at: date(820_456_200.875))

        #expect(try JSONDecoder().decode(PracticeSession.self, from: Data(written.utf8)) == expected)
    }

    private func date(_ secondsSince2001: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: secondsSince2001)
    }
}
