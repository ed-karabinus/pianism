import Foundation
import PianismCore
import PianismPersistence
import Testing

/// Integration tests against real files in a fresh temporary directory.
final class FilePracticeTotalsTests {
    let directory: URL
    let file: FilePracticeTotals
    let totals = PracticeTotals(day: Date(timeIntervalSince1970: 1_798_761_600), finished: 25 * 60 + 3.5)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "FilePracticeTotalsTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = FilePracticeTotals(fileURL: directory.appending(path: "practice-totals.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("GLN-2: no file means no totals")
    func noFileNoTotals() {
        #expect(file.read() == nil)
    }

    @Test("GLN-2: totals written by one process are read back exactly by another, and the next write replaces them")
    func totalsSurviveInFile() throws {
        try file.write(totals)
        let otherProcess = FilePracticeTotals(fileURL: directory.appending(path: "practice-totals.json"))

        #expect(otherProcess.read() == totals)

        let later = PracticeTotals(day: totals.day, finished: 60 * 60)
        try file.write(later)

        #expect(otherProcess.read() == later)
    }

    @Test("GLN-2: a file that can't be read counts as no totals")
    func unreadableFileIsNoTotals() throws {
        try Data("not totals".utf8).write(to: directory.appending(path: "practice-totals.json"))

        #expect(file.read() == nil)
    }
}
