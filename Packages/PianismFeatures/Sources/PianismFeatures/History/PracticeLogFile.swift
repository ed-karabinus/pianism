import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// EXP-1's CSV file, made only once it's shared, so it holds history as it is then, not when Settings opened.
struct PracticeLogFile: Transferable {
    let make: @Sendable () async throws -> Data

    /// A file rather than data, as AirDrop ignored the suggested name of data and called the file
    /// "comma-separated values-….csv" (device check S10, 2026-11-13), where Save to Files kept it. A shared file
    /// keeps its own name wherever it goes (device check S11).
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(try write(try await file.make()))
        }
        .suggestedFileName(fileName)
    }

    static var fileName: String { String(localized: "Pianism sessions", bundle: .module) + ".csv" }

    /// Writes `data` as "Pianism sessions.csv" in a folder of its own in the temporary directory, so two shares
    /// never write the same file.
    static func write(_ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try data.write(to: url)
        return url
    }
}
