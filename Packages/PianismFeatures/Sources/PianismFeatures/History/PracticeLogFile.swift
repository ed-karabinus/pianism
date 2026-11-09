import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// EXP-1's CSV file, made only once it's shared, so it holds history as it is then, not when Settings opened.
struct PracticeLogFile: Transferable {
    let make: @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in try await file.make() }
            .suggestedFileName(String(localized: "Pianism sessions", bundle: .module) + ".csv")
    }
}
