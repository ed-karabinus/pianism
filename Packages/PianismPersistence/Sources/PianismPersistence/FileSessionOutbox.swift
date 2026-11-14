import Foundation
import PianismCore
import os

/// A ``SessionOutbox`` that keeps each waiting session in its own JSON file in `directory`, so adding
/// or removing one never rewrites another (ADR 0007). Writes are atomic, so a crash never leaves half
/// a file, and no folder means nothing is waiting.
public struct FileSessionOutbox: SessionOutbox {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func sessions() throws -> [PracticeSession] {
        bringBackReadable()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        // Atomic writes pass through temporary files, which never end in .json.
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            // Unreadable right now, or removed since the listing: try again next time.
            guard let data = try? Data(contentsOf: file) else { return nil }
            if let session = Self.session(in: data) { return session }
            moveAside(file)
            return nil
        }
    }

    public func add(_ session: PracticeSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: file(for: session.id), options: .atomic)
    }

    public func remove(id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: file(for: id))
        } catch CocoaError.fileNoSuchFile {}
    }

    public func unreadableCount() -> Int {
        let files = try? FileManager.default.contentsOfDirectory(at: unreadable, includingPropertiesForKeys: nil)
        // Only moveAside(_:) puts files here, each a waiting session's.
        return files?.count ?? 0
    }

    /// Unreadable/, where a waiting file this version can't read waits for one that can (#87).
    private var unreadable: URL { directory.appending(path: "Unreadable") }

    /// Moves each file in Unreadable/ that this version can now read back among the waiting, as after an update
    /// that reads what a newer version wrote (#87). One already back, written again since, wins.
    private func bringBackReadable() {
        let files = try? FileManager.default.contentsOfDirectory(at: unreadable, includingPropertiesForKeys: nil)
        for file in files ?? [] {
            guard let data = try? Data(contentsOf: file), Self.session(in: data) != nil else { continue }
            let back = directory.appending(path: file.lastPathComponent)
            if FileManager.default.fileExists(atPath: back.path) {
                try? FileManager.default.removeItem(at: file)
            } else {
                try? FileManager.default.moveItem(at: file, to: back)
            }
        }
    }

    /// The session `data` holds, if this version can read it. One check for both directions, so a file can't move
    /// aside and back again in the same version.
    private static func session(in data: Data) -> PracticeSession? {
        try? JSONDecoder().decode(PracticeSession.self, from: data)
    }

    /// Moves a file whose contents aren't a session, as after an update changed the format, to
    /// Unreadable/, so it can't hold back the others. It's kept there, counted, for a version that can read it.
    private func moveAside(_ file: URL) {
        let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")
        do {
            try FileManager.default.createDirectory(
                at: unreadable, withIntermediateDirectories: true)  // mutate:ignore - its parent was just listed
            try FileManager.default.moveItem(at: file, to: unreadable.appending(path: file.lastPathComponent))
            logger.error(  // mutate:ignore - a log line; no test reads logs
                "Moved aside an unreadable waiting session: \(file.lastPathComponent, privacy: .public)")
        } catch {
            logger.error(  // mutate:ignore - a log line; no test reads logs
                "Couldn't move aside \(file.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
