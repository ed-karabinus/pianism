import CloudKit
import Foundation
import Synchronization
import Testing

@testable import PianismPersistence

/// Whether History says iCloud isn't syncing (SYN-1). The account's status is faked, since a test process has no
/// iCloud entitlement, and making a `CKContainer` there would crash.
struct HistoryStoreSyncTests {
    struct Failed: Error {}

    @Test("SYN-1: a store that doesn't sync never says it isn't syncing")
    func storeThatDoesntSyncSaysNothing() async {
        var notSyncing = HistoryStore(url: URL(filePath: "/dev/null/History.store")).notSyncing.makeAsyncIterator()

        #expect(await notSyncing.next() == nil)
    }

    @Test(
        "SYN-1: with no iCloud account, a restricted one or one not ready, the store says it isn't syncing",
        arguments: [
            (CKAccountStatus.noAccount, true), (.restricted, true), (.temporarilyUnavailable, true),
            (.available, false), (.couldNotDetermine, false),
        ])
    func statusSaysWhetherSyncing(status: CKAccountStatus, isNotSyncing: Bool) async {
        var notSyncing = HistoryStore.notSyncing { status }.makeAsyncIterator()

        #expect(await notSyncing.next() == isNotSyncing)
    }

    @Test("SYN-1: when the account's status can't be read, the store says nothing is wrong")
    func failedCheckSaysSyncing() async {
        var notSyncing = HistoryStore.notSyncing { throw Failed() }.makeAsyncIterator()

        #expect(await notSyncing.next() == false)
    }

    @Test("SYN-1: the store checks again whenever the iCloud account changes", .timeLimit(.minutes(1)))
    func checksAgainWhenAccountChanges() async {
        let status = Mutex(CKAccountStatus.noAccount)
        var notSyncing = HistoryStore.notSyncing { status.withLock { $0 } }.makeAsyncIterator()
        #expect(await notSyncing.next() == true)

        status.withLock { $0 = .available }
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)

        #expect(await notSyncing.next() == false)
    }
}
