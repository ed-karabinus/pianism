import Foundation

/// EXP-1's CSV file, written when Export is tapped, so it holds history as it is then, not when Settings opened.
///
/// It's written before the share sheet opens and shared as that file, which keeps its name everywhere, AirDrop
/// included. Shared as data, AirDrop called it "comma-separated values-….csv" (device check S10, 2026-11-13). Shared
/// as a file made when the sheet asked for it (#253), the sheet waited 2 s trying to open it in place, and AirDrop
/// sent it as text, "text-….txt" (device check S11, 2026-11-14).
struct PracticeLogFile: Sendable {
    let make: @Sendable () async throws -> Data

    /// Makes the CSV and writes it, ready to share.
    func written() async throws -> URL {
        try Self.write(try await make())
    }

    static var fileName: String { String(localized: "Pianism sessions", bundle: .module) + ".csv" }

    /// Writes `data` as "Pianism sessions.csv" in a folder of its own in the temporary directory, so two exports
    /// never write the same file.
    static func write(_ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try data.write(to: url)
        return url
    }
}
