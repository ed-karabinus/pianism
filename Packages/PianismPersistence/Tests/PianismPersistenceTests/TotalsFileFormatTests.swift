import Foundation
import PianismCore
import PianismPersistence
import Testing

/// Totals as builds have written them to devices, read through the adapter that reads them there (ADR 0010).
/// Every build must read every sample, or the widget shows 0 until the app next writes. Never edit a sample; when
/// the format changes, add one.
final class TotalsFileFormatTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "TotalsFileFormatTests-\(UUID())")

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("GLN-2: a day's totals, as first written, still read")
    func totalsRead() throws {
        let written = #"{"day":820396800,"finished":1503.5}"#

        #expect(
            try totals(from: written)
                == PracticeTotals(day: Date(timeIntervalSinceReferenceDate: 820_396_800), finished: 1503.5))
    }

    /// Reads `json` as the totals file.
    private func totals(from json: String) throws -> PracticeTotals? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "practice-totals.json")
        try Data(json.utf8).write(to: file)
        return FilePracticeTotals(fileURL: file).read()
    }
}
