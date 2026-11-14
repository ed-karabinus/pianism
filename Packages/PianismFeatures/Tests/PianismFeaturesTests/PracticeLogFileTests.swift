import Foundation
import Testing

@testable import PianismFeatures

/// Only the share sheet's AirDrop on an iPhone shows whether the name survives: on a Mac, the system keeps the suggested
/// name of shared data too, so a test of the sharing passes on the old code (device check S11).
struct PracticeLogFileTests {
    @Test("EXP-1: each share writes the export as \"Pianism sessions.csv\" in a folder of its own")
    func eachShareHasItsOwnFolder() throws {
        // Given the CSV's bytes
        let data = Data("started_at,ended_at\n".utf8)

        // When two shares write them
        let first = try PracticeLogFile.write(data)
        let second = try PracticeLogFile.write(data)
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        // Then each is a file of that name holding them, in a different folder
        #expect(first.lastPathComponent == "Pianism sessions.csv")
        #expect(try Data(contentsOf: first) == data)
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
    }
}
