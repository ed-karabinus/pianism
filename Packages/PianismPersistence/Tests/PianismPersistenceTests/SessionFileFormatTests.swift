import Foundation
import PianismCore
import PianismPersistence
import Testing

/// Sessions as builds have written them to devices, read through the adapters that read them there:
/// the running-session file (ADR 0003) and the outbox (ADR 0007). Every build must read every sample,
/// or an update loses the session that was running, and every waiting one. Never edit a sample; when
/// the format changes, add one.
final class SessionFileFormatTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SessionFileFormatTests-\(UUID())")
    let id = UUID(uuidString: "3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90")
    let vienna = TimeZone(identifier: "Europe/Vienna")

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("SES-6: a running session, as written before time zones were recorded, still reads")
    func runningSessionWithoutTimeZoneReads() throws {
        let written = #"{"id":"6B1E2A4C-0F5D-4C3B-9A8E-2D7F1C3B5A90","startedAt":820454400,"pauses":[]}"#
        let oldID = try #require(UUID(uuidString: "6B1E2A4C-0F5D-4C3B-9A8E-2D7F1C3B5A90"))

        #expect(try runningSession(from: written) == PracticeSession(id: oldID, startedAt: date(820_454_400)))
    }

    @Test("SES-6: a paused session, as written since time zones were recorded, still reads")
    func pausedSessionReads() throws {
        let written =
            #"{"pauses":[{"start":820454700.5,"end":820454760.75},{"start":820455000.125}],"#
            + #""startedAt":820454400.25,"id":"3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90","#
            + #""timeZone":{"identifier":"Europe\/Vienna"}}"#
        var expected = PracticeSession(id: try #require(id), startedAt: date(820_454_400.25), timeZone: vienna)
        try expected.pause(at: date(820_454_700.5))
        try expected.resume(at: date(820_454_760.75))
        try expected.pause(at: date(820_455_000.125))

        #expect(try runningSession(from: written) == expected)
    }

    @Test("SES-6, ADR 0007: an ended session, as written since time zones were recorded, still reads in both places")
    func endedSessionReads() throws {
        let written =
            #"{"pauses":[{"start":820454700.5,"end":820454760.75}],"endedAt":820456200.875,"#
            + #""startedAt":820454400.25,"id":"3F2B8C1E-7A4D-4E9B-8C2F-1D5A6B7C8E90","#
            + #""timeZone":{"identifier":"Europe\/Vienna"}}"#
        var expected = PracticeSession(id: try #require(id), startedAt: date(820_454_400.25), timeZone: vienna)
        try expected.pause(at: date(820_454_700.5))
        try expected.resume(at: date(820_454_760.75))
        try expected.stop(at: date(820_456_200.875))

        #expect(try runningSession(from: written) == expected)
        #expect(try waitingSessions(from: written) == [expected])
    }

    /// Reads `json` as the running-session file.
    private func runningSession(from json: String) throws -> PracticeSession? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "running-session.json")
        try Data(json.utf8).write(to: file)
        return try FileRunningSessionStore(fileURL: file).current()
    }

    /// Reads `json` as the only file in the outbox.
    private func waitingSessions(from json: String) throws -> [PracticeSession] {
        let outbox = directory.appending(path: "Outbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: outbox.appending(path: "\(UUID().uuidString).json"))
        return try FileSessionOutbox(directory: outbox).sessions()
    }

    private func date(_ secondsSince2001: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: secondsSince2001)
    }
}
