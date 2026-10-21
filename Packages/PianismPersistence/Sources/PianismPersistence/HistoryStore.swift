import CloudKit
import CoreData
import Foundation
import SwiftData
import Synchronization
import os

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

    /// Opens the store now rather than at first use, so iCloud sync starts at launch (SYN-1). If it can't, the
    /// first use reports why (ADR 0007).
    public func open() {
        _ = try? container()
    }

    /// Fires after each save to this store once it has opened, by this app or by an iCloud import (SYN-1).
    /// Whatever runs on it must only read, or each change would cause another.
    public var changes: some AsyncSequence<Void, Never> {
        let url = url.standardizedFileURL
        return NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)
            .filter { ($0.userInfo?[NSPersistentStoreURLKey] as? URL)?.standardizedFileURL == url }
            .map { _ in () }
    }

    /// Whether iCloud can't sync this store, with no account or one that isn't ready, as it is now and after each
    /// change to the account (SYN-1). A store that doesn't sync says nothing.
    public var notSyncing: AsyncStream<Bool> {
        guard let cloudKitContainer else { return AsyncStream { $0.finish() } }
        // Held by the check, as the account-changed notification comes only while a container exists.
        let container = CKContainer(identifier: cloudKitContainer)
        return Self.notSyncing { try await container.accountStatus() }
    }

    /// Whether the account `status` reports can't sync, now and after each change to the account.
    static func notSyncing(status: @escaping @Sendable () async throws -> CKAccountStatus) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                // Made before the first check, so a change during it isn't missed.
                let changes = NotificationCenter.default.notifications(named: .CKAccountChanged).map { _ in () }
                continuation.yield(await isNotSyncing(status))
                for await _ in changes {
                    continuation.yield(await isNotSyncing(status))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func isNotSyncing(_ status: () async throws -> CKAccountStatus) async -> Bool {
        do {
            switch try await status() {
            case .noAccount, .temporarilyUnavailable: return true
            case .available: return false
            // Whoever restricted the device chose this, and the person using it can't sign in.
            case .restricted: return false
            // Can't tell: saying nothing beats a wrong notice.
            case .couldNotDetermine: return false
            @unknown default: return false
            }
        } catch {
            logger.error("Couldn't check the iCloud account: \(error, privacy: .public)")
            return false
        }
    }

    private static let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

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

        /// Debug only: creates schema v1's record types and fields in the Development environment of
        /// `cloudKitContainer`, from a scratch store, ready to check and deploy (SYN-1, ADR 0008). It needs
        /// an iCloud account, so the owner runs it on a signed-in simulator.
        public static func initializeCloudKitSchema(cloudKitContainer: String) throws {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: HistorySchemaV1.models) else {
                preconditionFailure("Schema v1 has no Core Data model")
            }
            let directory = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchema-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let description = NSPersistentStoreDescription(url: directory.appending(path: "Schema.store"))
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainer)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "Schema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: (any Error)?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
    }
#endif
