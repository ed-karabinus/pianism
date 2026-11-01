# Plan: feat(SYN-1): Show changes from iCloud while the app is open
Fable (high) Plan agent, 2026-10-21. Read-only; nothing built.

1. HistoryStore gains `changes`: an AsyncSequence of `.NSPersistentStoreRemoteChange` filtered to the store URL (standardized). PianismApp keeps `store` and adds `.task { for await _ in store.changes { history.refresh(); tags.refresh() } }`. No new protocol.
   - Fallback: AsyncStream(bufferingNewest(1)) plus addObserver, if Swift 6 rejects the Notification element.
2. **Don't call practice.refresh().** Practice shows nothing from the synced store, and its refresh writes (outbox archive), so a change would cause another change. Refresh handlers must be read-only.
3. SwiftData doesn't expose the remote-change option; history tracking is on (the fixtures have ATRANSACTION). **Gate: write adapter test 1 first and run make test-adapters. If the notification never fires, stop and ask the owner.**
4. The notification also fires for local saves, adding one extra read-only refresh. No loop, no debounce.
5. HistoryModel.refresh() adds `editing?.tags.refresh()`.
6. Tests:
   - adapter: another HistoryStore on the same file saves → reported; another file → not reported; a tag via SwiftDataTagLibrary → reported. Each with timeLimit 1 min.
   - view model: an open editor's tags show a rename after refresh.
   - e2e: a DEBUG hook PIANISM_SYNC_ARRIVES_SECONDS=n, where a second HistoryStore (no CloudKit) on the same file saves a session and the piece "Synced piece". The picker shows it without a tap, and History shows Today 30 min. The comment "all eight" becomes "nine".
   - device-checklist row 3: the iPhone shows a tag from S1 within 60 s (B2, live push).
7. Planted bugs: drop the URL filter; the wrong notification name; forget tags.refresh; forget editing refresh; .task in the wrong place.
8. Size: ~30 production lines (~20 without the hook), ~150 total.
9. ADR 0004 amendment: the signal comes from the store, not the ports; no history read; Practice isn't refreshed. Conflicts with plan-syn1 PR3/item 8 (practice.refresh).
10. Owner questions:
    - (a) the e2e real-time wait vs E4 (precedent: cap/nudge);
    - (b) HistoryStore opens lazily, so mirroring starts only when History opens or a session ends. Eager open at launch is about 1 line.

A1 with one sim: yes. An app delete removes the store and mirroring metadata, so a reinstall does a full import. Check the Console has both records before deleting, to avoid a false fail. For no false pass, prefer a sim that never held the records. A3–A5 need two stores holding the record at once, but never two sims booted together: a shut-down sim is "offline", and its exports wait. A2 works on one sim. B2 (live push) needs a real device.

**Owner decisions (2026-10-21):** (a) add the e2e hook and test; (b) open the store at launch, in this PR.
