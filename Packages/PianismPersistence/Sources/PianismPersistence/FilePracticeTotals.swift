import Foundation
import PianismCore
import os

/// A day's finished practice in one JSON file in the App Group container, which the app writes and the widget
/// extension reads (ADR 0010).
///
/// Every write is atomic, so a read in the other process sees the old file or the new one, never half of one;
/// that is all the coordination a single writer needs. No file, or one that can't be read, means no totals.
public struct FilePracticeTotals: Sendable {
    private let fileURL: URL
    private static let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "glance")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file every process in `appGroup` shares, or `nil` if this process isn't in that group.
    public init?(appGroup: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        self.init(fileURL: container.appending(path: "practice-totals.json"))
    }

    public func write(_ totals: PracticeTotals) throws {
        // Readable after the first unlock, so the widget can draw on the Lock Screen.
        try JSONEncoder().encode(totals).write(
            to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The stored totals, or `nil` if there are none: the app hasn't written any yet, or wrote them in a format this
    /// build can't read. A wrong read only costs a 0 until the app next writes, so nothing is kept for diagnosis.
    public func read() -> PracticeTotals? {
        do {
            return try JSONDecoder().decode(PracticeTotals.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Self.logger.error("Couldn't read the practice totals: \(error, privacy: .public)")
            return nil
        }
    }
}
