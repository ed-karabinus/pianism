import Foundation
import SwiftData
import Synchronization

/// The SwiftData store that holds finished sessions and tags (ADR 0004, as amended by ADR 0006).
///
/// Sync through iCloud is off until SYN-1 (#15) deploys the schema.
public final class HistoryStore: Sendable {
    /// The record version this app writes; it changes only records up to it (ADR 0006).
    static let recordVersion = 1

    private let url: URL
    /// The store once it has opened. Until then, each call tries to open it and throws why it
    /// couldn't, so a passing failure such as a full disk heals itself, and the app keeps running:
    /// History says it couldn't load, and finished sessions wait in the outbox (ADR 0007).
    private let opened = Mutex<ModelContainer?>(nil)

    /// A store at `url`, which is created, with its folder, on first use.
    public init(url: URL) {
        self.url = url
    }

    func container() throws -> ModelContainer {
        try opened.withLock { opened in
            if let opened { return opened }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let container = try ModelContainer(
                for: Schema(versionedSchema: HistorySchemaV1.self),
                migrationPlan: HistoryMigrationPlan.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            opened = container
            return container
        }
    }
}
