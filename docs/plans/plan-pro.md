# Pro, per-piece stats and CSV export: implementation plan

Written 2026-11-07 by an Opus 5.5 plan agent (read-only), checked against the code by a Fable 5.1 agent, and changed for that check and for a probe of real StoreKit on CI (#205, closed). The owner approved the plan and [ADR 0012](../adr/0012-pro-from-storekit-and-free-count-from-records.md) on 2026-11-07.

**No CloudKit schema change and no deploy anywhere here.** Pro comes from StoreKit, the free count from existing records, and HIS-4 and EXP-1 from existing fields (ADR 0009).

Path key: `Core/`, `Features/` and `Persistence/` are `Sources/` of `Packages/PianismCore`, `PianismFeatures` and `PianismPersistence`.

## 1. PR order

| # | Title | Main files | Prod / test lines | Proves |
|---|---|---|---|---|
| 1 | `feat(PRO-1): Know on- or offline whether Pro is unlocked, with Restore in Settings` | `Core/ProStore.swift`, `Core/InMemoryProStore.swift`, new `Packages/PianismPurchases`, `Features/Pro/ProModel.swift`, `SettingsView`, `RootView`, `App/PianismApp.swift`, `Makefile`, pbxproj, `AppUITests/Pianism.storekit`, `Config/UITests.xcconfig` | 280 / 300 | Entitlement, Restore, offline and refund, with real StoreKit on iOS 27 and a fake store on all four simulators |
| 2 | `feat(PRO-3): Show what Pro offers and its price, and buy it, only when asked` | `Features/Pro/PaywallView.swift`, `ProModel`, `RootView`, `WelcomeView`, `Core/Analytics.swift`, ADR 0011 | 200 / 200 | Only a tap opens it, it lists only what exists, and the welcome says auto-start is Pro |
| 3 | `feat(PRO-2): Give the first 5 piano sessions free, then start them only with Pro` | `Core/SessionHistory.swift`, `Core/FreeTaste.swift`, `InMemorySessionHistory`, `FlakyHistory`, `Persistence/SwiftDataSessionHistory.swift`, `PracticeModel`, `PracticeView` | 130 / 280 | The 5th starts, the 6th doesn't, and deleting gives nothing back |
| 4 | `feat(HIS-4): Show where time goes per piece, with played and bench time from a piano` | `Core/PieceStats.swift`, `PracticeSession`, `HistoryModel`, `Features/History/PieceStatsView.swift`, `HistoryView` | 200 / 240 | Totals match History, and the split is honest |
| 5 | `feat(EXP-1): Export every session as a CSV file through the share sheet` | `Core/PracticeLogCSV.swift`, a Transferable in Features, a Settings row | 125 / 210 | The file is correct. First to cut if the date slips |

PRO-1 and PRO-3 are the Musts, so they go first. PRO-2 is a Should on paper but blocks release in practice: without the gate, Pro sells nothing. The queue on #179 still puts the MIDI-2 reconnect first, with an audit slot about every two feature PRs.

The welcome line moved to PR 2 from PR 3, because #53 says it ships with Pro even if the free 5 change. None of these waits for an open PR. HIS-4 doesn't need #204, as `TagIndex` is already on main. Conflicts with open PRs are mechanical: `PracticeTests.swift`, `Localizable.xcstrings`, `docs/decisions.md`, `docs/device-checklist.md`.

## 2. Testing StoreKit

| Layer | What runs | Where | Covers |
|---|---|---|---|
| Fake store | `InMemoryProStore` through a Debug hook | All four simulators, every PR | Screens, gates, what each outcome shows |
| Real StoreKit | `SKTestSession` from the UI test process, against `AppUITests/Pianism.storekit` | iOS 27, iPhone and iPad, every PR; skipped on iOS 26 | Purchase, refund, Ask to Buy, bought before launch, unreachable store, the default wiring |
| Sandbox | A dev-signed build or TestFlight, on the owner's devices | Each milestone gate | What no simulator shows, listed in §4 |

What the probe showed (#205):

- `SKTestSession` works through `build-for-testing` and `test-without-building`, signed to run locally, with no scheme change and no account. The `.storekit` file in `AppUITests/` lands in the test bundle and not in the app.
- **CI, iOS 27 (Xcode 27.2):** iPhone passed all 4 cases. iPad passed 3, as one Ask to Buy approval missed a 30 s wait with retries off. So the real tests allow longer than that, and PR 1 measures them on CI before relying on them.
- **CI, iOS 26 (Xcode 26.6, OS 26.5):** none pass. The product never loads, and `buyProduct` throws `notEntitled`, on both devices, so those tests skip there. The scheme's StoreKit reference wasn't tried, as it's reported refused for this signing on 26.5. It can be tried later if iOS 26 coverage matters.
- **This Mac, iOS 27.0 and 27.2:** all pass, with three repeats on one simulator. The certificate failure reported on 27.0.x [10] didn't appear.

Traps:

- **`askToBuyEnabled` persists on a simulator across runs.** Set it in every test, or a later run's purchase comes back pending. Reproduced twice, and gone when reset.
- Importing `StoreKitTest` fails under `GCC_TREAT_WARNINGS_AS_ERRORS`, because Apple's own header uses a deprecated type. `Config/UITests.xcconfig` needs `OTHER_SWIFT_FLAGS = $(inherited) -Xcc -Wno-error=deprecated-declarations -Xcc -Wno-deprecated-declarations`.
- `setSimulatedError` reaches the app, surfacing as `systemError(unknown)`. Reset it at the end of the test.
- `currentEntitlements` can stay empty after a purchase on iOS 26.4 and later [11]. That's why Pro's last known state is kept (§3).
- Failed purchases may show dialogs despite `disableDialogs` [14], so don't test them through real StoreKit.
- The file belongs in `AppUITests/`, as synchronized groups would ship it from `App/`.

The real tests don't exercise a mismatch with App Store Connect: the `.storekit` test only shows the file matches the core's ID. Nor does anything automated run a Release build's wiring, so the hook is `#if DEBUG` and the default path is the real store, which the iOS 27 tests run in Debug. Sandbox rows cover the rest.

For sandbox, the owner needs the product in App Store Connect and a Sandbox Apple Account. Signing and capabilities don't change: there's no entitlement key for in-app purchase [12].

## 3. Design

Port in the core, with no StoreKit import:

```swift
public protocol ProStore: Sendable {
    func offer() async throws -> ProOffer   // displayPrice from StoreKit
    func isEntitled() async -> ProStatus    // .entitled, .revoked, or .unknown when nothing says either
    func purchase() async throws -> PurchaseOutcome  // .purchased, .pending, .cancelled
    func restore() async throws
    var changes: AsyncStream<Void> { get }
}
```

- **`InMemoryProStore` (core):** for previews, tests and the hook, like `InMemorySessionHistory`.
- **`StoreKitPro` (`PianismPurchases`):** starts its `Transaction.updates` task in init, from `PianismApp.init`, as Apple says to at launch [23] and a `.task` is too late. It finishes transactions. A pure mapping of `(productID, verified, revocationDate)` is tested on macOS. `.unverified` never grants. Compare it with Apple's sample in the PR [31].
- **`ProModel` (`@MainActor @Observable`, features):** holds `isPro`, `offer`, `isShowingPaywall` and `canAutoStart`, and is passed by init like `analytics`.
- **The last known state (the owner's decision):** `ProModel` stores `isPro` in `UserDefaults`. A verified entitlement sets it. An empty answer leaves it. Only a verified transaction with a `revocationDate` clears it, from `updates` or `Transaction.all`. With nothing stored yet and no answer, gates allow, so no one sees a lock flash at launch.
- **`PracticeModel`:** takes an `autoStart` closure defaulting to true, so existing test call sites don't change.
- **The gate:** only a new start, before `PracticeModel.swift:223` when `session == nil`. Resume, running sessions and tapped Start are untouched. `keepsScreenAwake` (:435) stops holding the screen on for a locked user.
- **The hook (Debug only):** `PIANISM_STORE=free|pro`, env for scripting buy, offer and restore, Darwin notifications for granted or revoked while open, and `PIANISM_AUTO_LOGGED=n`. `launch()`, `warmUp` and `LaunchTests` set it, so ordinary tests never reach StoreKit. The real tests leave it unset.

| Case | Behaviour |
|---|---|
| Pending (Ask to Buy) | "Waiting for approval", can close; `updates` unlocks later |
| Cancelled | Paywall stays, no error |
| Network down | No price (never hardcoded), a retry line; Restore and Close still work |
| Restore finds nothing | "No purchase found"; a cancelled sign-in stays silent |
| Refunded | Pro turns off quietly, a running session finishes, data stays |
| Launched offline | Last known state |
| Second device | `updates` or next launch, no Restore needed |
| Mac "Designed for iPad" | Same code [30], one device row |

**Free count (ADR 0012).** Add `autoLoggedIDs() throws -> Set<UUID>` to `SessionHistory`.

- **What it counts:** raw records with `source == "midi"`, deleted ones included, plus outbox MIDI sessions. Starts stay free while there are fewer than 5.
- **Why deleting can't reset it:** `SwiftDataSessionHistory.swift:90-96` clears only the note and tags on delete, and ADR 0006 never purges.
- **When it counts:** on save, so short runs (`SessionRecorder.swift:156`) and timer sessions use nothing. It's fetched at the gate, not cached. A store failure allows the start.
- **Per Apple Account:** through sync, 3 on an iPhone and 2 on an iPad use all 5. ADR 0012 lists the generous gaps.

**HIS-4:**

- Total and 30 days sum `day.part(of:).practiced` (`PracticeDay.swift:28-33`), so they match History, over today plus the previous 29 days. Waiting sessions in the outbox count, as they do in History.
- It covers pieces only, archived included, with merges resolved through `TagIndex`.
- Bench is span minus played (spec MIDI-R2, ADR 0009), clipped per day to the 30-day window, so the closing 5 s counts as bench.
- Timer and manual sessions have no split, so Played plus Bench won't equal Total. Label it "From sessions your piano started", and hide it with no MIDI data.

**EXP-1:** one row per stored session, waiting ones included, oldest first: `started_at,ended_at,practiced_seconds,paused_seconds,source,tags,note`. ISO 8601 in the session's own zone, `Z` if it has none. Whole seconds. RFC 4180 with CRLF and a BOM. `ShareLink` with `DataRepresentation(.commaSeparatedText)`.

## 4. Coverage

| Row | Automated test | Planted bugs it must catch | Device |
|---|---|---|---|
| PRO-1 $14.99 non-consumable | Adapter test parses `.storekit` (ID equals the core's, type, price); real test shows `$14.99` | Hardcoded price; ID typo | S1 |
| PRO-1 $9.99 schedule | None, no code | n/a | S9 |
| PRO-1 Restore | Features (found, empty, cancelled, failed); `testRestorePurchasesInSettingsUnlocksPro` | No re-read after sync; cancel shown as error | S2 |
| PRO-1 offline | Mapping tests; `aProUserLaunchingOfflineStaysPro`; real test with the store unreachable | `.unverified` grants; revoked grants; entitlement needs `offer()`; an empty answer clears Pro | S3 |
| Pending, refund, second device | Features; real tests on iOS 27; fake store via notify | Pending unlocks; revocation ignored | S4, S5, S6, S7 |
| PRO-2 first 5, then Pro | `FreeTaste`; `theFifthPianoSessionStartsTheSixthDoesNot`; deleted and duplicate persistence tests; E2E seeded at 4 | `<=`; reads `sessions()`; counts at start; counts timer; gates resume | S8 |
| PRO-2 data stays | E2E: a locked user keeps History and Start | Gate placed in `start()` | |
| PRO-2 welcome line | Extend `PracticeTests.swift:1110-1145` for "while Pianism is open" and "first 5" | Phrase dropped | |
| PRO-3 only on tap | `testThePaywallShowsOnlyWhenAProFeatureIsTapped` | Shows at launch when locked; shows on a refused note | |
| PRO-3 contents | Same test plus the accessibility audit | No Close; no Restore; no included list | |
| HIS-4 totals | Core: 30-day boundary, midnight, DST, merged counted once | -30 window; `elapsed` instead of day parts; merges unresolved | |
| HIS-4 split | Core: closing 5 s is bench, timer has no split | Closing pause dropped; timer counted as played | |
| EXP-1 contents | Core: quoting, zone, merged, waiting, deleted | Undoubled quotes; raw IDs; UTC; fractional seconds | S10 |
| EXP-1 share sheet | E2E: sheet opens | Button not wired | |

New `docs/device-checklist.md` rows, added with their PRs:

- S1: sandbox purchase on iPhone.
- S2: reinstall shows Pro without Restore, and Restore works.
- S3: airplane-mode launch after force-quit.
- S4: Ask to Buy through Xcode.
- S5: refund through Transaction Manager with the app open.
- S6: Mac.
- S7: iPhone buys while iPad is open.
- S8: free count after delete and reinstall with iCloud.
- S9: App Store Connect shows $9.99 ending 31 Jan, then $14.99. A screen check, so #52 isn't held past launch.
- S10: CSV in Numbers and Excel, with accents intact.

## 5. Decisions

**Settled by the owner, 2026-11-07:**

- This plan and ADR 0012, counting the free 5 from session records.
- Product ID `com.edkarabinus.Pianism.pro`.
- The spec's testing row: real StoreKit on iOS 27 on every PR, a fake store on all four simulators, sandbox on a device.
- Keep the last known Pro state until a refund.
- The free 5 are per Apple Account.

**Still to ask, each with the PR it affects:**

| # | PR | Decision | Recommendation |
|---|---|---|---|
| D3 | 2 | Paywall words | "One purchase, no subscription", the included list with "while Pianism is open", and the store's price only. No "launch price" text, as the app can't track the schedule |
| D4 | 2 | Where the paywall opens | A Settings row plus locked features. It never interrupts anyone, and gives App Review a way in without a piano |
| D5 | 2 | Drop `Paywall.purchased` and `Paywall.restored` from ADR 0011 | Drop them. Sending them fits Apple's Purchase History type [26], which the label doesn't declare. It loses paywall-to-purchase conversion, which sales ÷ downloads can't give. If kept, the label and `App/PrivacyInfo.xcprivacy` must declare it |
| D6 | 3 | Practice line | "N free piano sessions left", shown only with a piano connected, then "Sessions that start themselves are part of Pro" with a link. No modal |
| D7 | 4 | What free users see | A locked row that opens the paywall, no preview. The week's by-piece stays free. EXP-1 works the same way |
| D8 | 4 | Where stats live | A row under the week in History, pieces only, with the words "Played" and "On the bench" |
| N4 | 4 | A session with several pieces | Counts fully toward each, labelled |
| D9 | 5 | Export | In Settings › History, with notes and source included |
| N3 | 5 | User text in the CSV | Verbatim, with RFC 4180 quoting. A `'` prefix against formula injection would rewrite "- slow practice" in a file promised to be theirs, and here the reader and author are the same person |
| D10 | App Store Connect | Family Sharing | Off at launch. Turning it on is permanent, and it can come later |
| N5 | 1 | S1 to S3 on TestFlight | Yes, as a TestFlight build is the Release wiring, and sandbox purchases are free there. The owner uploads |

**The owner's App Store Connect steps:**

| Step | When |
|---|---|
| Create the non-consumable with availability matching #56 and #57, its display name and description, plus a Sandbox account [29][25] | Before S1, not before PR 1 merges |
| $14.99 base price plus a Temporary Price Change to $9.99 ending 2027-01-31 [27] | Before #59; read the end date on screen |
| Paywall review screenshot | After PR 2 |
| Attach the purchase to the v1.0 draft, required for the first one [28] | At #59 |
| App Review notes on reaching the paywall without a piano | At #59 |

## 6. Sources

Opened by the plan agent, and those marked ✓ also by the checking agent:

- [8] https://developer.apple.com/forums/thread/826971 ✓
- [10] https://developer.apple.com/forums/thread/801578 ✓
- [11] https://developer.apple.com/forums/thread/820813 ✓
- [12] https://developer.apple.com/forums/thread/738035 ✓
- [14] https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
- [23] https://developer.apple.com/documentation/storekit/transaction/updates
- [25] https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
- [26] https://developer.apple.com/app-store/app-privacy-details/ ✓
- [27] https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases/ ✓
- [28] https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/
- [29] https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/
- [30] https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos
- [31] https://developer.apple.com/documentation/storekit/implementing-a-store-in-your-app-using-the-storekit-api

Not verified: that `currentEntitlements` works with no network at all, beyond the simulated store failure, which needs S3; CloudKit's purge on iCloud sign-out, taken from ADR 0008; the share sheet's element name under XCUITest; App Store Connect's end-date time zone.
