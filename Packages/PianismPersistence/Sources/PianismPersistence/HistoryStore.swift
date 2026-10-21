import Foundation
import SwiftData
import Synchronization

/// The SwiftData store that holds finished sessions and tags (ADR 0004, as amended by ADR 0006).
///
/// It syncs through iCloud only when given a CloudKit container (SYN-1).
public final class HistoryStore: Sendable {
    /// The record version this app writes; it changes only records up to it (ADR 0006).
    static let recordVersion = 1

    private let url: URL
    private let cloudKitContainer: String?
    /// The store once it has opened. Until then, each call tries to open it and throws why it
    /// couldn't, so a passing failure such as a full disk heals itself, and the app keeps running:
    /// History says it couldn't load, and finished sessions wait in the outbox (ADR 0007).
    private let opened = Mutex<ModelContainer?>(nil)

    /// A store at `url`, which is created, with its folder, on first use, and synced through the private
    /// database of `cloudKitContainer`, if given.
    public init(url: URL, cloudKitContainer: String? = nil) {
        self.url = url
        self.cloudKitContainer = cloudKitContainer
    }

    var configuration: ModelConfiguration {
        ModelConfiguration(url: url, cloudKitDatabase: cloudKitContainer.map { .private($0) } ?? .none)
    }

    func container() throws -> ModelContainer {
        try opened.withLock { opened in
            if let opened { return opened }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let container = try ModelContainer(
                for: Schema(versionedSchema: HistorySchemaV1.self),
                migrationPlan: HistoryMigrationPlan.self,
                configurations: configuration
            )
            opened = container
            return container
        }
    }
}

#if DEBUG
    extension HistoryStore {
        /// Debug only: adds `count` sessions as a newer version might write them, which this one can't rebuild, so
        /// end-to-end tests can see History count them (HIS-1). A prepared store file could replace this (#88).
        public func addUnshowableSessions(_ count: Int) throws {
            let context = ModelContext(try container())
            for _ in 0..<count {
                let record = SessionRecord()
                record.version = Self.recordVersion + 1
                // A pause with no end, which this version can't read.
                record.pauses = Data(#"{"pauses":[{"start":0}]}"#.utf8)
                context.insert(record)
            }
            try context.save()
        }
    }
#endif
