import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// EXP-1's CSV file, made only once it's shared, so it holds history as it is then, not when Settings opened.
struct PracticeLogFile: Transferable {
    let make: @Sendable () async throws -> Data

    /// Data, not a file, though AirDrop then names it "comma-separated values-….csv" (Save to Files keeps the name).
    /// Shared as a file made on demand (#253), the sheet took about 2 s longer to open, as iOS waited to open it in
    /// place, and AirDrop sent it as text, "text-….txt" (device check S11, 2026-11-14). See
    /// docs/decisions/2026-11-14-the-export-is-shared-as-data.md.
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in try await file.make() }
            .suggestedFileName(String(localized: "Pianism sessions", bundle: .module) + ".csv")
    }
}
