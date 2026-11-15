import Foundation
import Testing

@testable import PianismFeatures

/// Only the share sheet on an iPhone shows whether the name survives and the sheet opens at once: on a Mac, the system
/// keeps the suggested name of shared data too (device check S11).
struct PracticeLogFileTests {
    @Test("EXP-1: each export writes \"Pianism sessions.csv\" in a folder of its own")
    func eachExportHasItsOwnFolder() throws {
        // Given the CSV's bytes
        let data = Data("started_at,ended_at\n".utf8)

        // When two exports write them
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

    @Test("EXP-1: an export that fails for want of space says so, and any other failure says storage")
    func failureSaysWhy() {
        // Given the errors a full disk gives, from Foundation and from the system, and another
        let foundation = CocoaError(.fileWriteOutOfSpace)
        let system = POSIXError(.ENOSPC)
        let other = CocoaError(.fileReadNoPermission)

        // When each becomes a failure
        // Then a full disk is out of space, and the other is storage
        #expect(PracticeLogFile.Failure(foundation) == .outOfSpace)
        #expect(PracticeLogFile.Failure(system) == .outOfSpace)
        #expect(PracticeLogFile.Failure(other) == .storage)
    }
}
