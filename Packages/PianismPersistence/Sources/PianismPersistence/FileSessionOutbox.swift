import Foundation
import PianismCore

/// A ``SessionOutbox`` that keeps each waiting session in its own JSON file in `directory`, so adding
/// or removing one never rewrites another (ADR 0007). Writes are atomic, so a crash never leaves half
/// a file, and no folder means nothing is waiting.
public struct FileSessionOutbox: SessionOutbox {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func sessions() throws -> [PracticeSession] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        // Atomic writes pass through temporary files, which never end in .json.
        return try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(PracticeSession.self, from: Data(contentsOf: $0))
        }
    }

    public func add(_ session: PracticeSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: file(for: session.id), options: .atomic)
    }

    public func remove(id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: file(for: id))
        } catch CocoaError.fileNoSuchFile {
            // Already gone, as after a crash between removing it and returning.
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
