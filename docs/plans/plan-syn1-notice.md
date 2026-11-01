# Plan: feat(SYN-1): Say in History when iCloud isn't syncing (Opus xhigh Plan agent, 2026-10-21)
Branch syn-1-not-syncing-notice, stacked on #98 (it touches the same five files).

## Design
- **HistoryStore** (`import CloudKit`): `public var notSyncing: AsyncStream<Bool>`.
  - It finishes at once if there's no container. Otherwise it creates `CKContainer(identifier:)` and calls `Self.notSyncing { try await container.accountStatus() }`.
  - Internal `static func notSyncing(status:)` is the test seam. It listens for `.CKAccountChanged` first, yields the mapped status, then re-checks on each notification; `onTermination` cancels.
  - Mapping: `.noAccount`, `.restricted` and `.temporarilyUnavailable` mean true. Anything else, including a thrown error, means false, and errors are logged.
- **HistoryModel:** `public var isNotSyncing = false`, set by the app.
- **HistoryView:** a private `notSyncingNotice`, styled like the unshowable notice (footnote, secondary, `icloud.slash`, combined for accessibility).
  - It goes in the List after the existing notices, and in the empty state's `ContentUnavailableView actions:`.
  - The empty state gets `.accessibilityElement(children: .contain)` before its identifier.
  - Two previews; `Previews.preview(notSyncing:)`.
- **RootView:** `AccessibilityID.historyNotSyncing = "history.not-syncing"`. Localizable gains one string.
- **PianismApp:** a second `.task`: `for await v in historyStore.notSyncing { history.isNotSyncing = v }`.
- **Text:** "Your history isn't syncing. In Settings, sign in to iCloud and turn it on for Pianism."

## Tests
- **Adapter, HistoryStoreSyncTests:**
  1. no container → finishes;
  2. parameterised over the 5 statuses plus a throwing check;
  3. re-checks on `.CKAccountChanged` (timeLimit).
- **No view-model test** (a flag only).
- **e2e `testHistorySaysWhenICloudIsntSyncing`:** the real signed-out status (`PIANISM_SYNC=1` is already set). Empty History shows `history.empty` plus the notice. Start/stop, then one session plus the notice. Screenshots.
  - The failure message mentions signed-in simulators.
  - It automates checklist row 1, so delete row 1 and keep the S1/S2 note.
- **Checklist:** add an account-change row (A6/D7) on Sync S2: the per-app switch off and on, sign out, sign in.
- **ADR 0008 "Signing out":** add a sentence; don't promise that history returns (Q7).

## Size and risks
- Size: ~80 production, ~170 total.
- Risk 1: what `accountStatus` reports when only Pianism's iCloud switch is off is unknown.
- Risk 2: `.CKAccountChanged` may not fire for the per-app switch.
- Risk 3: an unentitled `CKContainer` traps.
- Risk 5: AX5 clipping in the empty state.

## Owner questions (recommended answers used, pending Ed)
1. Wording: one line for all three states.
2. Placement: History only, top of the list and under "No practice yet"; no dismiss, no button.
3. States: noAccount, restricted, temporarilyUnavailable. Not couldNotDetermine, errors, or sync-off-by-build.
4. Setup/sync errors such as the key failure: not in M1.
5. No test switch.
6. Delete row 1 and add the account-change row.
7. Don't promise that history returns on sign-in.

Decision numbers on #15: the notice is decision 3, sign-out purge is decision 6, encrypting note is decision 7.
