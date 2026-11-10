import PianismCore
import Testing

/// The ``ProStore`` contract, checked on the fake that previews and view-model tests rely on, so a change to how it
/// answers fails here and not only in a screen's tests.
struct InMemoryProStoreTests {
    @Test("PRO-1: by default a restore finishes, finds nothing and leaves Pro unknown")
    func restoreFindsNothingByDefault() async {
        // Given a store set up with nothing but defaults
        let store = InMemoryProStore()

        // When a restore runs
        let outcome = await store.restore()

        // Then it finished without unlocking Pro
        #expect(outcome == .finished)
        #expect(await store.status() == .unknown)
    }

    @Test("PRO-1: a restore unlocks Pro only when it finishes and finds a purchase")
    func restoreUnlocksOnlyWhenItFinds() async {
        // Given two stores that would find a purchase, one whose restore is cancelled
        let finds = InMemoryProStore(restoreFinds: true)
        let cancelled = InMemoryProStore(restoring: .cancelled, restoreFinds: true)

        // When each restores
        let found = await finds.restore()
        let stopped = await cancelled.restore()

        // Then only the finished one unlocked Pro
        #expect(found == .finished && stopped == .cancelled)
        #expect(await finds.status() == .entitled)
        #expect(await cancelled.status() == .unknown)
    }

    @Test("PRO-3: a purchase unlocks Pro only when it goes through, and the next one's outcome can be changed")
    func purchaseUnlocksOnlyWhenBought() async {
        // Given a store whose purchases are cancelled
        let store = InMemoryProStore(buying: .cancelled)

        // When one is bought, then the next is set to go through and bought
        let first = await store.purchase()
        let unchanged = await store.status()
        await store.set(buying: .purchased)
        let second = await store.purchase()

        // Then the cancelled one left Pro unknown, and the second unlocked it
        #expect(first == .cancelled && unchanged == .unknown)
        #expect(second == .purchased)
        #expect(await store.status() == .entitled)
    }

    @Test("PRO-1: a status set from outside, as a refund sets it, replaces the old one and says so")
    func setStatusSaysSo() async {
        // Given a store with Pro
        let store = InMemoryProStore(status: .entitled)

        // When a refund revokes it
        await store.set(.revoked)

        // Then the status is revoked, and a change was announced
        #expect(await store.status() == .revoked)
        #expect(await changeArrives(on: store.changes))
    }

    /// Whether a change comes within two seconds, so a store that stays silent fails the test rather than hanging it.
    private func changeArrives(on changes: AsyncStream<Void>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
