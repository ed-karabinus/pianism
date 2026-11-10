# 12. Pro comes from StoreKit behind a port, and the free count from the session records

- Status: accepted
- Date: 2026-11-07
- Amends: [ADR 0004](0004-synced-data-model.md)
- Issues: #52 (PRO-1), #53 (PRO-2)
- Plan: [plan-pro.md](../plans/plan-pro.md)

## Context and problem statement

Pro is a one-time purchase. Its check has to work offline, and the core package can't import StoreKit,
because it runs on Linux. PRO-2 gives the first 5 piano sessions free, and ADR 0004 left open where that
count lives, saying only that it isn't derived from history, because deleting sessions would reset it.

Schema v1 is deployed to CloudKit Production. Adding a field is permanent and costs a deploy (ADR 0008).

Real StoreKit can't be tested on all of CI. A probe on 2026-11-07 (#205) ran a purchase, a refund, Ask to
Buy and an unreachable store through `SKTestSession` on CI's four simulators. On iOS 27 they work: iPhone
passed all 4, and iPad 3, as one Ask to Buy approval missed a 30 s wait with retries off. On iOS 26 none
pass, because the product never loads.

## Considered options

For the free count:

1. **A new synced field or record.** Follows ADR 0004's wording, but costs a permanent Production deploy.
2. **A counter on the device, in `UserDefaults` or the keychain.** Needs no deploy, but each device counts
   separately, and it has to be kept in step with saves that can fail and wait in the outbox.
3. **Count the session records with `source == "midi"`, deleted ones included.** Needs nothing new.

For Pro's status:

1. **Read Apple's answer fresh on every launch, storing nothing.** Exact, but forum reports describe
   `Transaction.currentEntitlements` coming back empty after a successful purchase on iOS 26.4 and 26.5.
2. **Keep the last known state, and let only a refund clear it.**

## Decision

**A `ProStore` port in the core,** with a StoreKit 2 adapter in a new `PianismPurchases` package, and an
in-memory store for tests and previews. The adapter starts listening to `Transaction.updates` at launch.
An unverified transaction never grants Pro. The product ID is `com.edkarabinus.Pianism.pro`.

**Keep the last known state.** Pianism stores that the person has Pro when Apple confirms it, on this device.
An empty answer leaves it as it is. Only a verified transaction with a revocation date clears it. The owner
decided this on 2026-11-07: a customer who paid should never see Pro disappear.

**Count the free sessions from the records (option 3).** A deleted session keeps its record and its `source`
(`SwiftDataSessionHistory`, ADR 0006), so deleting can't win one back. Waiting sessions in the outbox count
too. IDs go in a set, so a retried save or a synced duplicate counts once. A session uses up a free one when
it's saved, so a run too short to keep and a timer session use none. The count is read when a piano session
is about to start, not cached, so a stale value can't allow a 6th or refuse a 5th. The owner chose this, and
that the 5 are per Apple Account, on 2026-11-07.

*Amended 2026-11-08 (PRO-2, the owner's call):* while any are left, the count is read at each start. Once it
finds all 5 used, later notes don't read it again until the next refresh, such as the app coming to the front or a
session saving, so a locked piano doesn't read history at every key press. Pro is asked first, and live, so buying
unlocks at once. The count only goes down if the local data is wiped, and the next refresh reads it then.

**Testing:** real StoreKit on every PR on iOS 27, a scripted fake store on all four simulators, and sandbox
checks on a device. The owner authorized this change to the spec's testing table on 2026-11-07.

## Consequences

- Good: no CloudKit schema change and no deploy. The app's entitlements and CI's signing don't change.
- Good: nothing in the core or the features knows about StoreKit, so they stay tested on every simulator.
- Bad: a device can show Pro for a while after a refund, until it hears about it. A jailbroken device could
  edit the stored state. Both cost little at this price.
- Bad: a reinstall or a new device has no stored state, so if Apple's answer is empty there, Pro stays locked
  until it recovers, or until Restore Purchases.
- Bad: the free count can be generous. A reinstall allows more until iCloud has imported the records. With
  iCloud off or signed out, it starts again. A session deleted while it's still only in the outbox leaves no
  record. All of these favour the user, and none can charge anyone unfairly.
- Bad: through sync, 3 sessions on an iPhone and 2 on an iPad use all 5.
- Bad: nothing automated runs real StoreKit on iOS 26, or in a Release build. Device rows cover this.
- Bad: importing `StoreKitTest` fails under `GCC_TREAT_WARNINGS_AS_ERRORS`, as Apple's own header uses a
  deprecated type, so the UI test target relaxes that one warning (`Config/UITests.xcconfig`).
- To verify on a device: everything in the plan's sandbox rows, as no simulator can show them.
