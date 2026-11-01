# SYN-1 (#15) plan — drafted 2026-10-20 by an Opus xhigh planning agent (read-only)

Sources it read: CLAUDE.md, pr-reviewer.md, #15 + spike comment, ADRs 0001–0007, PianismPersistence, PianismApp, Config, ci.yml, spike commit 99686c6, spec (SYN-1, NFR-3, NFR-9) via Claude Docs.

**Blocker:** NFR-9 says "no background modes", but the spike only got live pushes with `UIBackgroundModes: remote-notification`, and Apple's SwiftData-sync guide requires it. Owner decides (Q1).

## 1. Scope
In: the existing `HistoryStore` (sessions + user tags) mirrored to the private database; the capability; a Debug schema initializer; refreshing when iCloud brings records (ADR 0004's promised change signal); a one-line notice when iCloud isn't syncing; the production deploy; the device checklist.
Out: conflict UI (ADR 0006 accepts last writer wins); merge screen/commands (TAG-4 #29, M4; `mergedInto` resolution already ships); a sync on/off setting (iOS's iCloud switches cover it); quota/error UI (logged only); the running session (ADR 0003), widget summary (GLN-2), CKSyncEngine.

## 2. PRs (order 1 → 2 → 3∥4 → ⚠ deploy → 5; each < ~250 changed lines)
| # | PR | Prod | Contents |
|---|---|---|---|
| 1 | Capability, sync off | ~45 | Entitlements: container, CloudKit, `aps-environment development`, `icloud-container-environment = $(PIANISM_CLOUDKIT_ENV)` (Debug `Development`, Release `Production`, in xcconfig). Partial `Config/Info.plist` as in the spike (if Q1 yes). `HistoryStore(url:cloudKitContainer:)` — nil = local only; tests pass nil. App passes the container only in Debug with `PIANISM_SYNC=1`. Test: the configuration's URL is the one passed. |
| 2 | Schema for CloudKit | ~45 | Debug `PIANISM_INIT_CLOUDKIT_SCHEMA=1` runs `initializeCloudKitSchema()` on a scratch URL; names Apple's "Syncing model data across a person's devices" as the sample. macOS tests: every attribute optional or defaulted, no unique constraints, no relationships (via `makeManagedObjectModel(for:)`). A snapshot of v1's types/fields that may only grow. |
| 3 | Show other devices' changes | ~40 | `NSPersistentStoreRemoteChange` for this store calls `practice.refresh()` and `history.refresh()`. Integration test: two stores on one file. |
| 4 | Not-syncing notice | ~90 | `accountStatus()` + `CKAccountChanged` behind a seam; a History footnote (String Catalog, VoiceOver label, previews); view-model tests; CI e2e (no iCloud account) sees the notice and still saves. |
| 5 | Sync on | ~15 | Merges only after ⚠C. On by default; `PIANISM_SYNC=0` kept for one e2e test (saved with sync off still shows with sync on). Owner's export committed as `docs/cloudkit/schema-v1.ckdb`, plus checklist rows and their issues. |

## 3. ⚠ Irreversible / account-level steps
- **⚠A Container (owner).** `iCloud.com.edkarabinus.Pianism` exists; can never be deleted or renamed. Before PR1: confirm in CloudKit Console under team 259ZRX9QNZ and that the entitlement spells it exactly.
- **⚠B Development reset (owner),** only if Record Types lists anything besides `Users` before the initializer runs. Deletes all development records; check no real data is there first (Q2 keeps it out).
- **⚠C Production deploy (owner, Console → Deploy Schema Changes).** `CD_SessionRecord`, `CD_TagRecord` and every field exist forever (no rename/remove/type change). Before: snapshot test green on main; development lists only `Users`, the two types, and any type Core Data adds (e.g. `CDMR`) — no `CD_SpikeNote`; owner runs `xcrun cktool export-schema` on development (token from `cktool save-token`; CI never gets one); a reviewer compares field by field with ADR 0004/0006 tables incl. `CD_deletedAt`, `CD_targetTempo`; no custom indexes (Core Data doesn't query by field; believed addable later — verify). After: export production; must match development.
- **⚠D Owner's iPhone gets its first syncing build (owner).** Real history uploads to production. Before: download the app container in Xcode's Devices window as a backup; pass rehearsal D8 on another device.
- **⚠E App Store Connect record (owner, at TestFlight).** Freezes bundle ID. iCloud needs no ASC capability; the App ID's iCloud/Push capabilities came from automatic signing and can be turned off.
- **⚠F First upload.** `codesign -d --entitlements :-` on the exported app must show `aps-environment production` and `Production`. An uploaded build can't be deleted.

## 4. Existing local store
Same URL, same schema, no migration: stays at `Application Support/History/History.store`, schema v1 already meets CloudKit's rules; only `cloudKitDatabase` changes. Core Data should add its sync tables and upload existing rows on first open (D8 checks). No new URL (a copy = permanent code with half-copied failure states). App Group finding: SwiftData put the spike's store there only because it was given a name, not a URL — so keep an explicit URL; keep `HistoryStore` the only `ModelContainer` (with the entitlement, SwiftData's default `.automatic` would sync any default store); keep the store out of the App Group (ADR 0004: app process only; widget reads a summary file). The iPhone's leftover `SyncSpike.store` is harmless.

## 5. Testing
Automated: macOS schema rules + snapshot, store URL, change signal; notice view-model tests; CI e2e runs the CloudKit configuration on account-less simulators (proves offline use, no sign-in screen, and catches entitlements that stop the store opening — which would otherwise silently send every session to the outbox); `history-v1` fixture already covers `version` 2 records reading as read-only.
Not automatable: real CloudKit (CI never uses the owner's Apple ID; E4 bans real network in tests), live pushes (simulators get none), airplane mode.
Device checklist (one issue per row saying why manual), Debug `PIANISM_SYNC=1` (development); repeat D1 on Release after ⚠C:
- D1 stop a session on device A; open device B shows it within 60 s.
- D2 add a tag on B; A shows it after relaunch.
- D3 offline B records a session + tag; both arrive after reconnect (NFR-3).
- D4 delete on one device while the other, offline, edits its note: stays deleted on both, note doesn't return (also shows whether CloudKit mixes fields — ADR 0006's open question).
- D5 both offline edit the same session; record which wins.
- D6 both offline add "Ballade No. 1"; two tags, no crash (TAG-4 merges later).
- D7 sign out/in, and iCloud off for the app: notice shows; record which local history remains.
- D8 a device on the pre-sync build with history installs the syncing build; the other shows the same counts.
(The draft named "the iPad and a signed-in simulator" as A/B — WRONG: the owner's iPad A1893 can't run iOS 26. Available: owner's iPhone 18 Pro (iOS 27, real history) and simulators (no live pushes).)
ADR 0006/outbox under sync: outbox stays local (a waiting session syncs once history saves it); a stale outbox copy finds the saved record or its delete mark and changes nothing; an older version can't edit higher-`version` records.

## 6. Risks
CloudKit model rules (complies; PR2 keeps it); duplicate records (latest `modifiedAt` per `id`; delete marks every copy; same-name tags wait for TAG-4); mixed fields (last writer wins could combine a delete with another device's edit — D4/D5 decide whether reads need a rule); account changes (Core Data may remove the previous account's rows locally — test D7 on a test device, never the owner's iPhone); quota (uploads fail, data stays local, logged); `aps-environment` (Xcode should rewrite to production on App Store export — ⚠F checks; an Xcode-installed Release build using production may get no pushes but catches up when opened); UI-test data (a signed-in test simulator would upload test data to development — keep test simulators signed out).

## 7. Owner questions (with recommendations)
1. NFR-9 vs `remote-notification`: **amend NFR-9 to allow only this mode.** Without it, sync catches up when the app opens, and D1 goes away.
2. Release on Production, Debug on Development? **Yes** — real history never lands in development (which gets reset), however the build is installed.
3. Not-syncing notice in M1? **Yes** — passive History line, no button.
4. When to deploy? **Right after PRs 1–4, with no new fields.**

Critical files: PianismPersistence/HistoryStore.swift, HistorySchema.swift, App/PianismApp.swift, Config/Pianism.entitlements (+ App/Debug/Release.xcconfig), docs/device-checklist.md.

---
# Fable xhigh review (2026-10-20) — verdict: proceed; rework §4/§5 and Q2; extend ⚠C. **v1 schema needs no change.**
Owner priority (2026-10-20): existing local data may be wiped; the production schema must be right.
1. **Owner's iPhone never runs a Debug (Development) sync build.** Same store attached to Development then Production may confuse mirror metadata (purge or rows marked exported that never upload). Debug sync opt-in (`PIANISM_SYNC=1`), Release always on (drop PR5's "on by default"); e2e pass `PIANISM_SYNC=1`; rule in device-checklist: from ⚠D the iPhone runs only Release. With the owner's OK to wipe: delete + reinstall the app before its first syncing Release build. Pre-⚠C rows on simulators only.
2. **Sign-out purge** (NSPersistentCloudKitContainer removes mirrored rows on account change/sign-out/per-app iCloud off) is an owner decision (Q5).
3. **⚠C additions.** `initializeCloudKitSchema()` via `NSManagedObjectModel.makeManagedObjectModel(for: HistorySchemaV1.models)` (iOS 18+): scratch URL, removed after, signed-in device/sim on Development. Expected extras: `CD_entityName` on both types; `CD_pauses` + `CD_pauses_ckAsset`; `Users`; `CDMR` probably absent. Mapping: UUID→String, Date→Date/Time, Int/Bool→Int64, String→String, Data→Bytes+Asset, `[String]`→Bytes (initializer is the real check). Entity names = Swift class names (renaming later = new type). PR2 snapshot freezes entity names, attribute names, `NSAttributeType`, `isOptional`, `valueTransformerName`. Compare exported `.ckdb` text with a committed expected file. Indexes addable/removable after deploy.
4. **History tracking:** fixture stores have ATRANSACTION/ACHANGE → SwiftData enables persistent history by default; first mirroring load exports existing objects. (Backup/restore moot given owner's OK to wipe; if ever needed: Xcode Download/Replace Container; Settings → Apple Account → iCloud → Manage → Pianism → Delete data empties production.)
5. **Entitlements:** `$(PIANISM_CLOUDKIT_ENV)` expands in .entitlements; dev profiles allow both environments. Unverified: pushes to a dev-signed build on Production (B2 none = expected). PR1's CI may need `CODE_SIGNING_ALLOWED=NO` for simulator builds if team-less signing rejects iCloud/aps entitlements.
6. **NFR-9:** recommendation stands (remote-notification has no UI). Without it: no live updates. Optional 10-min control run on the spike branch.
7. **ADR 0006 under sync:** field- vs record-level LWW unknown; A3/A4 decide. Record-level → an edit after a delete resurrects the session. Fallback, no schema change: `delete()` also inserts a tombstone copy (new record, same `id`, `deletedAt` set); `shown(among:)` already treats any deleted copy as deleted.
8. **PRs:** PR3 also calls `tags.refresh()` (TagPickerModel.swift:111), filtered to this store's URL; amend ADR 0004 in one line. PR4 has no schema effect: deploy after PRs 1–3. Add a short ADR 0008 (environments per configuration, iPhone rule, deploy date, the `.ckdb`). PR5 shrinks to Release wiring.
9. Questions: Q1–Q4 plus Q5 sign-out purge, Q6 second device, Q7 Debug opt-in.

## Reworked device checklist
P = owner's iPhone (Release/Production only). S1, S2 = iPhone simulators signed into the owner's account (no live pushes; "arrives" = within ~5 s of relaunch).
Phase A (before ⚠C; Debug, `PIANISM_SYNC=1`, Development, S1↔S2): A1 tag+session on S1 → S2 relaunch shows both. A2 (NFR-3) Mac Wi-Fi off, S2 adds session+tag, Wi-Fi on, S1 relaunch shows them. A3 S1 deletes X; offline S2 edits X's note; online, relaunch both: deleted on both, note gone? (decides 7). A4 offline S1 edits X's note, S2 X's tags: winner, fields mixed? A5 both offline add "Ballade No. 1": two tags, no crash. A6 S2 signs out, then per-app iCloud off: notice; local history left; what returns on sign-in (decides Q5). A7 copy `history-v1.store` into S1, install syncing Debug; S2 shows 1 session, 3 tags; then Release (Production) over it on S1: rows survive? A8 schema initializer on S1; Console lists `Users` + two types; export `.ckdb`.
Phase B (after ⚠C; Production): B1 (⚠D) wipe/reinstall P with Release; S1 on Release: relaunch shows P's counts. B2 S1 adds tag "Sync check"; P open shows it within 60 s? (none = expected on dev-signed build); P deletes it after.
A second real device adds live pushes both ways, true airplane mode, safe sign-out tests, iPad layout, production APNs — best via a TestFlight tester with their own account.

---
# Fable addendum (owner priority: data loss OK, prod schema must be right) — supersedes findings 1, 4 and Phase B where they conflict
- §4/⚠D collapse: before the first syncing build, delete Pianism from the iPhone and install Release. No backup, no A7/D8 rehearsal. iPhone runs Release (Production); signed-in simulators run Debug (Development). Q2 stays yes.
- **⚠C completeness is the critical check:** production has no just-in-time schema; a field missing from the deploy makes every record that sets it fail to export. Expected export (commit as `docs/cloudkit/schema-v1.expected.ckdb`, diff real export against it):
  - `CD_SessionRecord`: `CD_entityName` STRING, `CD_id` STRING, `CD_startedAt` `CD_endedAt` `CD_modifiedAt` `CD_deletedAt` TIMESTAMP, `CD_pauses` BYTES + `CD_pauses_ckAsset` ASSET, `CD_tagIDs` BYTES (maybe + asset twin), `CD_note` `CD_source` `CD_timeZoneID` STRING, `CD_version` INT64.
  - `CD_TagRecord`: `CD_entityName`, `CD_id` `CD_kind` `CD_name` `CD_composer` `CD_mergedInto` STRING, `CD_isArchived` INT64, `CD_targetTempo` INT64, `CD_createdAt` `CD_modifiedAt` TIMESTAMP, `CD_version` INT64.
  - Plus `Users`; `CDMR` probably absent. Class and property names frozen.
- **Change now, while free:**
  1. **Timestamp precision bug (must ship with sync):** CloudKit TIMESTAMP = ms; `pauses` JSON keeps full doubles. Stopped-while-paused sessions (`pause.end == endedAt`) would replay a resume after the stop on the other device → hidden. Fix: clamp pause times into `[startedAt, endedAt]` in `session()` before replay + test with `pause.end` 0.4 ms past `endedAt`; amend ADR 0006 "round-trips exactly" → "exactly locally; ms through CloudKit". Check in A1.
  2. **Q8 encrypt `note`** via `@Attribute(.allowsCloudEncryption)` — now or never under that name. Recommend yes (only field with the user's own words; unreadable in Console; matters with Advanced Data Protection). Tag names stay plain.
  3. **Q9 `TagRecord.deletedAt: Date?`** — tags are archived-never-deleted, so a tag name lives in CloudKit forever. Adding later = older apps show nameless archived tag. Recommend yes if tag deletion is ever a feature; regenerate `history-v1` fixture.
  4. `tagIDs` contingency: if the initializer rejects `[String]`, switch to `Data` JSON like `pauses` before deploy.
- **Pre-deploy sequence (replaces ⚠C):** 1 PR0 = items 1–3 as decided (+ fixtures). 2 PR2 snapshot green (entity/attribute names, `NSAttributeType`, `isOptional`, `valueTransformerName`, `allowsCloudEncryption`). 3 Dev reset if anything but `Users`. 4 Initializer on a signed-in simulator. 5 `cktool export-schema` dev; diff vs expected file; reviewer signs off. 6 Real app on two sims (A1–A5) so every field incl. a delete and a tempo appears. 7 Deploy. 8 Export prod = dev; commit `docs/cloudkit/schema-v1.ckdb`. Standing rule: development holds nothing experimental before any later deploy (spikes get their own container or a reset).
- Questions: Q1–Q7 plus Q8 encrypt note, Q9 TagRecord.deletedAt. Backup/restore decisions dropped.

---
**For ADR 0008 (consequences), 2026-10-20:** encrypting `note` may make an iCloud encrypted-data reset (after losing every device and passcode) delete Pianism's whole iCloud history, not just notes (zone-level key loss; unverified). The owner accepts it: data loss is the natural consequence of that reset, and a surviving device's local copy should re-upload. Write it as a known consequence.

---
# PR "snapshot + initializer" plan (Opus xhigh, 2026-10-20)
Base: branch from #93 + merge #92 (both edit PianismApp DEBUG). Files:
- HistoryStore.swift `#if DEBUG` ext: `public static func initializeCloudKitSchema(cloudKitContainer:) throws` per Apple's "Syncing model data across a person's devices": NSPersistentStoreDescription (scratch URL, shouldAddStoreAsynchronously=false, cloudKitContainerOptions), `makeManagedObjectModel(for: HistorySchemaV1.models)`, NSPersistentCloudKitContainer, loadPersistentStores, `initializeCloudKitSchema()`, remove store. Differences: opt-in env not every Debug launch; scratch URL; throws not fatalError.
- PianismApp: `static let iCloudContainer` beside `appGroup`; DEBUG `PIANISM_INIT_CLOUDKIT_SCHEMA=1` → initializer, fatalError on throw; "all eight".
- scripts/cloudkit-fields.sh (~15 awk): cktool export → sorted `RecordType.field TYPE`, drop `"___` system fields, GRANT, QUERYABLE/SORTABLE/SEARCHABLE.
- docs/cloudkit/schema-v1-fields.txt: expected, from ADRs (+ CD_TagRecord.CD_deletedAt TIMESTAMP, CD_note ENCRYPTED STRING, Users.roles LIST<INT64>).
- HistoryStoreFormatTests: replace onlyNoteIsEncrypted with snapshot "schema v1 is exactly what the CloudKit deploy freezes": sorted line per entity.properties (type name table, optional/default-present, valueTransformerName, encrypted), uniquenessConstraints empty, and every attribute X.y appears as CD_X.CD_y in the fields file (via #filePath). Write expected from ADR tables first.
- device-checklist: general intro + "iCloud sync (SYN-1, #15)": row 1 iPhone…/iPad… sims stay signed out; sync sims named "Sync S1"/"Sync S2" (simulator-destination.sh can't pick them); row 2 initializer + export diff "Not run".
- ADR 0008 here (environments, iPhone rule, steps, dev-holds-nothing-experimental, encrypted-reset consequence) + README row + ADR 0006 "amended by 0008".
Size ~50 prod (~210 changed). tagIDs: transformable → BYTES (maybe _ckAsset); if initializer throws or A1 tags don't arrive → stop; separate model PR (owner approval) to JSON Data.
Planted: rename timeZoneID; drop encryption; encrypt name; targetTempo Int=0; tagIDs Set; .unique id; extra attribute/relationship; delete fields-file line; script with CD_SpikeNote and without CD_deletedAt.
Owner steps after merge: 1 simctl create "Sync S1"/"Sync S2" iPhone 17, sign in. 2 `xcrun cktool save-token --type management`; `cktool get-teams`. 3 export-schema --team-id 259ZRX9QNZ --container-id iCloud.com.edkarabinus.Pianism --environment development --output-file build/cloudkit/before.ckdb → only Users, else reset-schema (⚠B). 4 Debug build team-signed, install on S1 (idle Mac, one sim). 5 `SIMCTL_CHILD_PIANISM_INIT_CLOUDKIT_SCHEMA=1 xcrun simctl launch --console-pty "Sync S1" com.edkarabinus.Pianism`. 6 export → development.ckdb; `scripts/cloudkit-fields.sh … | diff docs/cloudkit/schema-v1-fields.txt -`; explain diffs on #15; reviewer signs off. 7 A1–A5 with SIMCTL_CHILD_PIANISM_SYNC=1; re-export; diff unchanged. 8 deploy PR: deploy, export production, raw diff vs development.
Open: defaults → record presence only; watchdog under simctl launch → rerun if killed; #filePath test → yes.
