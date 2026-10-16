import Foundation
import PianismCore

/// A ``RunningSessionStore`` that keeps the session in one JSON file, which the app and its
/// extensions share through the App Group container (ADR 0003).
///
/// Every access goes through `NSFileCoordinator`, so a change made by one process never interleaves
/// with a read or change made by another. Every write is atomic, so a crash never leaves half a
/// file. No file means no session.
///
/// Calls block while another process holds the file, which takes milliseconds.
public struct FileRunningSessionStore: RunningSessionStore {
    /// Where the session is stored.
    public let fileURL: URL

    /// Where an unreadable file is moved, so it is kept for diagnosis instead of being deleted.
    public var unreadableFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The store every process in `appGroup` shares, or `nil` if this process isn't in that group.
    public init?(appGroup: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        self.init(fileURL: container.appending(path: "running-session.json"))
    }

    /// The stored session. An unreadable file counts as no session.
    public func current() throws -> PracticeSession? {
        try coordinate(writing: false) { url in  // mutate:ignore - a write claim is also correct, only slower
            if case .session(let session) = try contents(of: url) { session } else { nil }
        }
    }

    /// Changes the stored session as one coordinated read-modify-write. If `change` throws, the
    /// file is left as it was. An unreadable file counts as no session, and is moved to
    /// ``unreadableFileURL`` before the change is written.
    public func update<Value: Sendable>(_ change: (inout PracticeSession?) throws -> Value) throws -> Value {
        try coordinate(writing: true) { url in
            let contents = try contents(of: url)
            var session: PracticeSession? = if case .session(let stored) = contents { stored } else { nil }
            let value = try change(&session)
            if case .unreadable = contents {
                // Keeps only the latest unreadable file. If removing an older one fails, so does the move.
                try? FileManager.default.removeItem(at: unreadableFileURL)
                try FileManager.default.moveItem(at: url, to: unreadableFileURL)
            }
            try write(session, to: url)
            return value
        }
    }

    private enum Contents {
        case none
        case session(PracticeSession)
        case unreadable
    }

    private func contents(of url: URL) throws -> Contents {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .none
        }
        // Any other read error, such as the device being locked since it started, is thrown: the
        // file may be fine. Only a file that was read but can't be decoded counts as unreadable.
        guard let session = try? JSONDecoder().decode(PracticeSession.self, from: data) else {
            return .unreadable
        }
        return .session(session)
    }

    private func write(_ session: PracticeSession?, to url: URL) throws {
        guard let session else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Already gone.
            }
            return
        }
        // Readable after the first unlock, so Live Activity buttons work on the Lock Screen.
        try JSONEncoder().encode(session).write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Runs `body` while holding a coordinated claim on the file, and rethrows its error.
    private func coordinate<Value>(writing: Bool, _ body: (URL) throws -> Value) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Value, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
                outcome = Result { try body(url) }
            }
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
                outcome = Result { try body(url) }
            }
        }
        if let coordinationError { throw coordinationError }
        // NSFileCoordinator calls the accessor exactly when it reports no error.
        guard let outcome else { throw CocoaError(.fileLocking) }
        return try outcome.get()
    }
}
