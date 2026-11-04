# Pianism — Full audit of `main`

- **Date:** 2026-11-03
- **Base:** `main` at `fea4df4` (`fix(MIDI-2): Don't list iOS's network MIDI session as a piano (#172)`), reviewed in the isolated `Pianism-review` worktree (detached HEAD). `Pianism` and `Pianism-piano` were not touched.
- **Method:** Five independent reviewers (core, features/UI, persistence/sync, MIDI/widgets/system, tests/CI/ship), each required to open the implementation and test bodies they cite, followed by an adversarial critic that re-read cited lines to falsify claims, one gap follow-up, and a synthesis. File:line references are against `fea4df4`.
- **Verification actually run:** `PianismCore` suite executed from a `/tmp` scratch copy — **113 tests in 12 suites passed**. Core hypotheses were additionally probe-tested in `/tmp` (see findings marked *probe-verified*). Persistence/features/MIDI findings rest on inspected code and test bodies; those suites were **not** executed in this pass (see *Unresolved*). No simulator or device run was done.

## Verdict

**No surviving Blockers. 8 Majors, ~30 Minors/Nits. The core is in unusually good shape; the risk sits at the edges: Bluetooth reconnection, CloudKit conflict behaviour, widget/Live Activity correctness, and release/CI gates.**

Do not read "no Blockers" as "ship it". Two items must be resolved before TestFlight regardless of severity label: the unverified `aps-environment` question (U-1 — it is either nothing or a production-push failure, and only a signed-archive dump can tell) and the missing archive/delivery path (AUDIT-08).

What is genuinely strong and should not be regressed: calendar/DST-correct day/week math, crash-safe outbox archiving (ADR 0007), stored-format backward compatibility by construction, tombstone deletion that erases user words, CloudKit encryption of user words, Swift 6 warnings-as-errors in depth, and requirement-tagged view-model tests. Details in *Strengths worth preserving*.

## Decisions (Ed, 2026-11-03)

Read this before the fix order below: these decisions replace it. Features stay first until code complete; the "Do" items go in as small PRs between feature PRs, about one for every two.

| Finding | Decision | Why |
| --- | --- | --- |
| AUDIT-01 Bluetooth reconnect | **After P5** | Device check P5 (paired from Pianism, piano off and on) decides it. If it doesn't come back, the CoreBluetooth reconnect suggested here is the fix, under #44. |
| AUDIT-02 Edit versus delete on two devices | **With the sync device checks** | Needs two devices; the result goes in ADR 0006, and a rule and test follow if a delete can lose. |
| AUDIT-03 Negative cap or MIDI timeout | **Later** | Only Debug's launch overrides can set one; Settings offers only positive values (#171, #174). A guard is cheap but not urgent. |
| AUDIT-04 Widget across midnight | **Do** | Confirmed: the midnight entry carries the running session over whole. |
| AUDIT-05 Widget cap with no totals file | **Do** | |
| AUDIT-06 No end-to-end run on push to main | **No** | Decided earlier: no end-to-end run on main; the nightly run covers it. |
| AUDIT-07 Mutation survivors don't fail a gate | **No** | Decided earlier (2026-10-19): mutation testing only for new logic, on changed lines. |
| AUDIT-08 No archive or delivery path | **Partly** | No CI archive: CI never uses the owner's Apple ID, and uploads stay his. A local release-build check before TestFlight settles U-1. |
| AUDIT-09 Widget privacy manifest | **No (disputed)** | The widget calls no required-reason API: it reads no settings since #170, only App Group files' contents. The app manifest's comment saying otherwise was stale and is fixed in this PR. |
| AUDIT-10 No Glance tests | **Later** | Worth doing; the widget and Live Activity device checks (W, L rows) come first. |
| AUDIT-11 WeekView has no preview | **Do** | Breaks CLAUDE.md's preview rule. |
| AUDIT-12 Stop dated before a pause | **Do** | Probe-verified, small core PR. |
| AUDIT-13 `lastNoteAt` and monotonicity | **Do** | Probe-verified, small core PR. |
| AUDIT-14 to AUDIT-18 | **After code complete** | Real but small. |
| AUDIT-19 Timeline ticks every second | **Do** | Battery cost for nothing while no session runs. |
| AUDIT-20 to AUDIT-33 | **After code complete** | Real but small polish. |
| AUDIT-34 Live Activity never stale | **Do** | With the Lock Screen pause PR (decided 2026-11-03), which changes the same code. |
| AUDIT-35, AUDIT-36 MIDI re-enumeration, failed setup | **After code complete** | Or with AUDIT-01 if P5 fails. |
| AUDIT-37 Notifications denied | **Do** | With SET-1's notification switch PR. |
| AUDIT-38 | **After code complete** | |
| AUDIT-39 CI hygiene | **No, mostly** | Reverses earlier choices on retries and checks; revisit only if flakes cost more than they do now. |
| U-1 `aps-environment` | **Before TestFlight** | Check a signed release build's entitlements; change nothing before that. |
| U-2, U-3 | **With the device checks** | |
| U-4, U-5 | **No action** | CI runs every suite on each PR. |

## Fix order (work top-down)

- [ ] **AUDIT-01** — Bluetooth piano never reconnects after a power cycle (Major)
- [ ] **AUDIT-02** — Concurrent edit-versus-delete across devices has no resolution (Major)
- [ ] **AUDIT-03** — Negative cap / MIDI timeout traps or ends sessions (Minor, crash-class — promoted)
- [ ] **AUDIT-04** — Widget miscounts a session crossing midnight (Minor, user-visible daily)
- [ ] **AUDIT-05** — Widget cap dropped when the totals file is missing/corrupt (Minor, critic-found)
- [ ] **AUDIT-06** — Merged `main` gets no end-to-end verification (Major, CI)
- [ ] **AUDIT-07** — Mutation survivors never fail any gate (Major, CI)
- [ ] **AUDIT-08** — No archive / App Store delivery path (Major, release)
- [ ] **AUDIT-09** — Widget extension has no privacy manifest (Major, App Store)
- [ ] **AUDIT-10** — `PianismGlance` (and `SystemPracticeGlance`) have zero unit tests (Major)
- [ ] Then the remaining Majors (AUDIT-11) and Minors (AUDIT-12…AUDIT-39) by subsystem.

---

## Majors

### AUDIT-01 — Bluetooth piano never reconnects after a power cycle

- **Where:** `Packages/PianismMIDI/Sources/PianismMIDI/CoreMIDINotes.swift:41`
- **Evidence:** The adapter only reacts to CoreMIDI `.msgObjectAdded` / `.msgObjectRemoved` / `.msgSetupChanged` via `connectAll()`. There is no `CBCentralManager`, `retrieveConnectedPeripherals`, or state-restoration logic anywhere in `Packages/`, `App/`, or `Widgets/`.
- **Impact:** Already failed on device (checklist M2): after piano off/on, iOS did not reconnect and Pianism heard nothing until manual re-pairing. This breaks the headline "practice fills itself in" flow for Bluetooth pianos. Checklist P5 is still *Not run yet*.
- **Fix:** In the MIDI adapter (or a small BLE helper it owns), keep a `CBCentralManager`, remember the paired peripheral identifier, and on power-on call `retrieveConnectedPeripherals` / `connect` so `MIDISetupChanged` fires again without opening `ConnectPianoView`.
- **Test to add:** Adapter-level test with a fake BLE central asserting a remembered peripheral is re-connected on `poweredOn`; plus complete device-checklist M2/P5 on hardware and record the result in `docs/device-checklist.md`.

### AUDIT-02 — Concurrent edit-versus-delete across devices has no app-level resolution

- **Where:** `docs/adr/0006-schema-v1-before-deploy.md:130`; `Packages/PianismPersistence/Sources/PianismPersistence/SwiftDataSessionHistory.swift:65` (`edit`), `:81` (`delete`)
- **Evidence:** ADR 0006 states CloudKit conflict handling is last-writer-wins and that an edit made on another device before sync can be lost. `edit` mutates only the locally shown copy; `delete` tombstones only local copies. No merge rule exists for a same-record CloudKit conflict, and no persistence test covers it.
- **Impact:** A note edit and a delete racing on two devices can lose the edit or resurrect a deleted session, depending on CloudKit field merging.
- **Fix:** Run the deferred two-device edit-vs-delete and edit-vs-edit checks, record the observed outcome in ADR 0006, and if a delete can lose, add a deterministic rule (e.g. `deletedAt` always wins on read after sync import).
- **Test to add:** Whatever the two-device run reveals, encode the winning rule as a `SwiftDataSessionHistory` test with duplicate copies (mirroring the existing duplicate-resolution tests), and tick the ADR 0006 checklist item.

### AUDIT-06 — Merged `main` gets no end-to-end verification

- **Where:** `.github/workflows/ci.yml:97`, gate at `:139`
- **Evidence:** The e2e job is `if: github.event_name != 'push'` and the app gate repeats that condition, so pushes to `main` run only core/lint/unused/adapters jobs.
- **Impact:** Two individually green PRs can break together on `main` undetected until the nightly cron (`ci.yml:17`).
- **Fix:** Run at least a smoke e2e matrix on push to `main`, or enable merge queue with required e2e before merge.
- **Test to add:** None (CI change) — verify by pushing a deliberately incompatible pair on a throwaway branch and showing the new gate catches it.

### AUDIT-07 — Mutation survivors never fail any gate

- **Where:** `scripts/mutate.py:99`; `Makefile:106`
- **Evidence:** `main` prints survivors and returns normally (no non-zero exit). `ci.yml` has no mutate job. The Makefile target mutates only Core + Persistence + System + MIDI, excluding the `PianismFeatures` view models (the largest tested surface) and `PianismGlance`.
- **Impact:** Untested logic can survive indefinitely; the milestone-only manual run is easily skipped. This contradicts the `CLAUDE.md` rule that mutation testing runs before milestone checks.
- **Fix:** Make `mutate.py` exit 1 when survivors lack `// mutate:ignore - <reason>`, and add a scheduled CI job covering Core, Persistence, and Features models with an allowlist file.
- **Test to add:** None — demonstrate the new exit code on a seeded mutant, then remove the seed.

### AUDIT-08 — No archive or App Store delivery path exists

- **Where:** `Config/Shared.xcconfig:29` (team), `:9` (versions); no `ExportOptions.plist`, archive job, or upload step in `ci.yml` / `Makefile`
- **Evidence:** `DEVELOPMENT_TEAM` lives only in the git-ignored `Config/Local.xcconfig`. `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION 1` are never bumped by automation.
- **Impact:** Release depends on one developer's local settings and a manual archive — high risk of wrong-team signing or duplicate build-number rejection at upload.
- **Fix:** Add an archive workflow with `ExportOptions.plist`, team from secrets, automatic build-number increment, plus a `make archive` target mirroring `make build`.
- **Test to add:** A dry-run archive on CI producing an `.ipa` whose entitlements are dumped in the job log (this also settles U-1 below).

### AUDIT-09 — Widget extension has no privacy manifest

- **Where:** `App/PrivacyInfo.xcprivacy:5`
- **Evidence:** The app manifest's own comment admits the widget adds required-reason API `1C8F.1` and needs a manifest of its own, yet only `App/PrivacyInfo.xcprivacy` exists. `Widgets/PracticeWidget.swift:53` reads App Group files via `FileRunningSessionStore` / `FilePracticeTotals`.
- **Impact:** App Store Connect required-reason / collected-data review can reject the appex or report inaccurate privacy (NFR-2).
- **Fix:** Add `Widgets/PrivacyInfo.xcprivacy` declaring the extension's accessed APIs with `1C8F.1` as applicable, and extend the `make build` privacy check to `plutil -lint` both bundles.
- **Test to add:** The extended `make build` check failing when either manifest is missing/invalid.

### AUDIT-10 — `PianismGlance` and the App glance adapter have zero unit tests

- **Where:** `Packages/PianismGlance/Package.swift:22`; `App/SystemPracticeGlance.swift:91`
- **Evidence:** `PianismGlance` declares only a library target — no `testTarget` — while carrying `GlanceCommands`, `LiveActivityIntents`, `StartPracticeIntent`, and `PracticeAttributes` contracts. `SystemPracticeGlance` (reconcile ordering/de-duplication, ActivityKit error swallowing) lives in `App/`, which `make test-adapters` cannot reach (ADR 0010). `PracticeWidget` / `PracticeLiveActivity` likewise have no test target, and device-checklist W1–W9 are all *Not run yet*.
- **Impact:** Intent routing, `ContentState` timer/`pausedAt` mapping, cap propagation, and activity reconciliation regress only in slow UI tests or on device.
- **Fix:** Add a `PianismGlanceTests` target covering `GlanceCommands` delegation, `PracticeAttributes.ContentState` mapping (paused/capped/uncapped), and intent `perform` paths with fakes; extract the activity-selection decision in `SystemPracticeGlance` into a pure function testable without ActivityKit.
- **Test to add:** The new suites themselves; complete W1–W9 before TestFlight.

### AUDIT-11 — `WeekView` has no `#Preview` at all

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/History/WeekView.swift:7`
- **Evidence:** The only view file with zero `#Preview` entries, despite containing a `Chart`, a swipe `DragGesture` (`:40`), a `DisclosureGroup` (`:60`), and an AX5-sensitive `@ScaledMetric` height (`:14`).
- **Impact:** Direct violation of the `CLAUDE.md` rule (*New views get `#Preview`s in light, dark and AX5*); chart layout and AX5 behaviour are unverified.
- **Fix:** Add WeekView previews (this week with tags, empty week, dark + AX5) using `HistoryModel.preview()` inside a `List`/`Section`.

---

## Minors — core (`PianismCore`)

### AUDIT-03 — Negative cap or MIDI timeout traps / ends sessions immediately *(promoted into fix order)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/PracticeSession.swift:98`; `Packages/PianismCore/Sources/PianismCore/MIDISettings.swift:5`
- **Evidence:** `practiceClock(cap:)` builds `practiceOrigin...(practiceOrigin + cap)` with no guard — a negative cap creates a `ClosedRange` with upper < lower, which **traps**. `SessionRecorder.end(atCap:)` and `MIDIDetector` expiry accept negative `MIDISettings` values without validation. Critic re-confirmed by reading the lines.
- **Fix:** Guard cap and `MIDISettings` intervals as non-negative at the `PracticeSession` / `SessionRecorder` boundary (clamp to `nil`/`0`), with tests for negative and zero values. Run `make test-core`.

### AUDIT-12 — Detector can emit an end effect the recorder cannot apply *(probe-verified)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/MIDIDetector.swift:125`
- **Evidence:** `stop(at:)` returns `end(afterLastNote: since, at: min(date, since + 5))` with no floor at `since`. Probe: a stop dated before a silence pause produced end at `t0+50` for a pause at `t0+80`; `SessionRecorder.end` threw `timeWentBackwards`, leaving the session paused while the detector had gone idle.
- **Fix:** Clamp the stop date to at least the pause/last-note date in `MIDIDetector.stop(at:)`; add a detector-plus-recorder test for a stop dated before the pause.

### AUDIT-13 — `lastNoteAt` is not part of the monotonicity invariant *(probe-verified)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/PracticeSession.swift:191` (`latestEvent`), `:196` (`checkCanChange(at:)`)
- **Evidence:** `latestEvent` considers only `startedAt` and pause boundaries. Probe: `noteLastPlayed` moved `lastNoteAt` from `start+70` back to `start+60`, and `pause(at: start+50)` was accepted after a note at `start+70`.
- **Impact:** A regressed `lastNoteAt` makes `MIDIDetector.sync` (`MIDIDetector.swift:146`) compute an earlier silence deadline and can pause away played time if any caller bypasses the detector's max logic.
- **Fix:** Include `lastNoteAt` in `checkCanChange(at:)`, or reject dates before `lastNoteAt` in `noteLastPlayed` / `pause` / `resume` / `stop`; add regression tests mirroring the probe.

### AUDIT-14 — Elapsed trusts decoded pauses with no validation *(probe-verified)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/PracticeSession.swift:74`
- **Evidence:** `elapsed(at:)` sums `(pause.end ?? end) − pause.start` with no ordering checks (`practiceSpans` at `:175` does guard empty spans). Probe: JSON with a pause end 50 s before its start decoded and reported elapsed 650 s for a 600 s session.
- **Impact:** A malformed or cross-version payload inflates day/week/recording totals above the session's wall-clock length, and can go negative for an over-long pause.
- **Fix:** Validate pauses on decode, or clamp each pause contribution and the final elapsed to the session span; add malformed-JSON tests (reversed pause, out-of-span pause).

### AUDIT-15 — One `InMemorySessionHistory` as both history and outbox loses the session *(probe-verified)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/InMemorySessionHistory.swift:62`
- **Evidence:** The `SessionOutbox` extension implements `add` as remove-plus-save, and `remove` (`:68`) deletes from the same `saved` array used as history. Probe: `archive(to: both, or: both)` returned the ended session but left `both.sessions()` empty.
- **Impact:** Previews/tests sharing one instance for both ports — which the class comment invites — silently lose practice after a successful archive.
- **Fix:** Keep separate saved/waiting storage, or document and enforce distinct instances; add archive tests for the shared-instance and deleted-then-outboxed cases.

### AUDIT-16 — `PracticeDay.group` does not enforce its finished-sessions contract *(probe-verified)*

- **Where:** `Packages/PianismCore/Sources/PianismCore/PracticeDay.swift:16`
- **Evidence:** `group(_:in:)` groups every session passed and totals each with `elapsed(at: .distantPast)` (`:22`). Probe: a running session appears as a day with total 0 and would contribute partial practice after pauses, contrary to the doc comment.
- **Fix:** Filter to ended sessions inside `group`, or rename/document the precondition; add a test with running and paused inputs.

### AUDIT-17 — No literal old-format JSON test; Mutex stores never stressed

- **Where:** `Packages/PianismCore/Tests/PianismCoreTests/PracticeSessionTests.swift:456`
- **Evidence:** Codable coverage is round-trip only via `JSONEncoder`/`JSONDecoder`; the `Mutex`-backed in-memory stores are tested only sequentially. Probe confirmed a payload missing only post-launch optional keys decodes, but nothing in the suite pins that.
- **Fix:** Add a literal minimal v1 JSON fixture test in core tests and a concurrent update/save stress test for the in-memory stores. (Persistence keeps its own format samples regardless — AUDIT strengths.)

## Minors — features / UI

### AUDIT-18 — `RootView` preview lacks dark and AX5 variants

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/RootView.swift:168`
- **Fix:** Add a `Dark, AX5` preview (`.preferredColorScheme(.dark).dynamicTypeSize(.accessibility5)`), matching `PracticeView:396` / `HistoryView:220`.

### AUDIT-19 — `TimelineView` ticks every second unconditionally

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeView.swift:54`
- **Evidence:** `TimelineView(.periodic(from: .now, by: 1))` wraps status + elapsed regardless of session state, and `PracticeView` stays alive under `TabView` on other tabs.
- **Impact:** Redraws and clock reads every second forever — battery cost exactly where NFR-10 worries about screen-on drain.
- **Fix:** Drive the timeline only while a session is running or a MIDI pause is pending; keep 1 s updates for the running case.

### AUDIT-20 — Unstructured `Task` for notification permission

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeView.swift:171`
- **Evidence:** `Task { await model.askForNudges() }` in the Remind-me button is detached from the view lifecycle, unlike the structured `.task` at `:178`; it cannot be cancelled and its ordering with `checkNudges` is unmanaged.
- **Fix:** Use a stored task or `.task(id:)` keyed to the banner, or document the fire-and-forget intent and keep `askForNudges` idempotent.

### AUDIT-21 — Tag picker has no empty / no-results state

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Tags/TagPickerView.swift:18`
- **Evidence:** With an empty library and empty query both sections are header-only; a failed load still shows that blank list behind the alert.
- **Fix:** Add `ContentUnavailableView` for no-tags / no-search-results (localized via `bundle: .module`), keeping the searchable Add flow.

### AUDIT-22 — Duplicated VoiceOver label on composer / tempo fields

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Tags/PieceDetailsView.swift:25`
- **Evidence:** Each `TextField` label (`Text("Composer")` at `:27`) sits inside a `LabeledContent` labelled again (`:32`); same for Target tempo (`:36`/`:45`). VoiceOver may announce "Composer, Composer"; UI tests see two matching labels.
- **Fix:** `.labelsHidden()` on the field (keeping the `LabeledContent` label), or drop the wrapper.

### AUDIT-23 — Start picker missing the identifier End has

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/History/SessionEditorView.swift:23`
- **Fix:** Add an `editorStart` case to `AccessibilityID` (`RootView.swift:148`) and apply it to the Start `DatePicker`, mirroring `editorEnd`.

### AUDIT-24 — Empty Bluetooth section renders on macOS

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Practice/ConnectPianoView.swift:35`
- **Evidence:** The section's only row is `#if os(iOS)` (`:37`), but header (`:49`) and footer (`:50`) are unconditional; macOS is a declared platform (`Package.swift:18`).
- **Fix:** Wrap the whole `Section` in `#if os(iOS)`, or add a macOS row explaining pairing is iOS-only.

### AUDIT-25 — `ElapsedTime` formatting has no direct unit tests

- **Where:** `Packages/PianismFeatures/Sources/PianismFeatures/Practice/ElapsedTime.swift:6`
- **Fix:** Add `ElapsedTimeTests` covering 0, 59, 60, 3599, 3600, and fractional-second truncation (`display()` / `spoken()`).

## Minors — persistence / sync / glance

### AUDIT-26 — History reads rescan and redecode the whole store twice per refresh

- **Where:** `Packages/PianismPersistence/Sources/PianismPersistence/SwiftDataSessionHistory.swift:21`
- **Evidence:** `sessions()` and `unshowableCount()` each call `read()`; `read()` fetches every `SessionRecord` unsorted/unbatched (`:32`) and JSON-decodes pauses/tagIDs for every record. `SwiftDataTagLibrary.tags()` likewise fetches every `TagRecord` (`:19`).
- **Fix:** Return sessions + unshowable count from one pass, add a fetch batch size or `startedAt` sort, and cache the count alongside `sessions()` in the caller. Run `make test-adapters`.

### AUDIT-27 — Duplicate resolution has no deterministic tie-break

- **Where:** `Packages/PianismPersistence/Sources/PianismPersistence/SwiftDataSessionHistory.swift:121`; `SwiftDataTagLibrary.swift:76`
- **Evidence:** `shown(among:)` picks `max` by `modifiedAt` only, from an unsorted fetch — while the code itself notes iCloud truncates timestamps to milliseconds (`:153`). Same-millisecond copies can resolve to different winners on different devices.
- **Fix:** Sort by `modifiedAt`, then a stable secondary key (`endedAt`, `createdAt`, `id`), in both adapters; add a same-millisecond test.

### AUDIT-28 — Outbox files lack the explicit file protection sibling stores set

- **Where:** `Packages/PianismPersistence/Sources/PianismPersistence/FileSessionOutbox.swift:32`
- **Evidence:** `add` writes with only `.atomic` (`:34`); `FileRunningSessionStore` and `FilePracticeTotals` both pass `.completeFileProtectionUntilFirstUserAuthentication`.
- **Fix:** Pass the same option in `FileSessionOutbox.add` and assert the attribute in a test, or document why the default suffices.

### AUDIT-29 — Widget converts every running-session read error into "no session"

- **Where:** `Widgets/PracticeWidget.swift:52`
- **Evidence:** `entry(at:)` uses `try?` on `FileRunningSessionStore.current()` (`:53`), discarding the store's deliberate locked-device-throws distinction, so the view offers Start (`:75`) during a transient read failure while a session may be running.
- **Fix:** Distinguish nil container from a thrown read error; hide/disable Start when session state is unknown.

### AUDIT-30 — Outbox drain not triggered when history recovers in the foreground *(critic-found)*

- **Where:** `App/PianismApp.swift:248`; `Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeModel.swift:358`
- **Evidence:** The `historyStore.changes` task calls only `history.refresh()` and `tags.refresh()`. The sole archive/`moveWaiting` caller is `PracticeModel.refresh()`, reached via `cameToFront` (scenePhase-active) or a Practice command/tick. `docs/plans/plan-syn1-live-refresh.md` deliberately avoids `practice.refresh()` there to prevent a write loop, but no alternative drain was added.
- **Impact:** Sessions that waited in the outbox during a SwiftData outage keep showing as waiting — and stay uneditable (`HistoryModel.swift:164` refuses waiting IDs) — for as long as the app stays foregrounded after recovery. No data loss; `waitingCount` also stays stale.
- **Fix:** On `historyStore.changes`, drain only when the outbox is non-empty (read-only count check gating one archive call). The second change event then finds an empty outbox and writes nothing, so no loop.

### AUDIT-31 — Tag changes on a missing/deleted tag fail silently *(Nit)*

- **Where:** `Packages/PianismPersistence/Sources/PianismPersistence/SwiftDataTagLibrary.swift:61`
- **Evidence:** `change(_:_:)` returns without error when `shown(among:)` is nil (`:64`), so rename/archive/set-details report success for a tag deleted on another device.
- **Fix:** Throw a TagDeleted/not-found error when copies exist but none show, mirroring `SessionDeleted` in `SwiftDataSessionHistory.edit`.

### AUDIT-32 — Corrupt totals silently discarded and overwritten *(Nit, acceptable per ADR 0010)*

- **Where:** `Packages/PianismPersistence/Sources/PianismPersistence/FilePracticeTotals.swift:33`
- **Fix:** Only if widget-zero reports need diagnosis: move the unreadable totals file aside once before overwriting, as the running-session store and outbox already do.

## Minors — MIDI / notifications / widgets / Live Activity

### AUDIT-04 — Widget miscounts a session crossing midnight *(promoted into fix order)*

- **Where:** `Widgets/PracticeWidget.swift:42` (timeline), view at `:101`
- **Evidence:** `getTimeline` eagerly builds `entry(at: midnight)` from App Group files read *now*: `finished` becomes 0 for the new day (`:57`) but the same running session is carried over, and the view counts the full `practiceClock` from its original `practiceOrigin`. Critic re-confirmed.
- **Impact:** A session started before midnight shows its entire elapsed (including yesterday's minutes) as today's total after midnight, until the app next reloads the widget.
- **Fix:** For a future-midnight entry, clamp the session contribution to time after midnight (drop or re-origin the session) instead of reusing today's session verbatim.

### AUDIT-05 — Widget cap dropped when the totals file is missing/unreadable *(critic-found, promoted)*

- **Where:** `App/SystemPracticeGlance.swift:60`
- **Evidence:** The cap write runs only `if capChanged, let written = lastWritten ?? file.read()`. In a fresh process `lastWritten` is nil and `FilePracticeTotals.read()` returns nil for a missing/corrupt file, so the cap is never persisted. The only other totals writer, `HistoryModel.refresh()`, does not run for a background intent launch.
- **Impact:** A widget-started session (`StartPracticeIntent`, which can launch in the background) whose totals file was deleted/corrupted gets `cap = nil` — `practiceClock` ends at `.distantFuture` — and counts past the SES-4 cap until the app is next foregrounded.
- **Fix:** When `capChanged` and no totals are readable, write a zero `PracticeTotals` for today (day from the session/calendar) carrying the cap, instead of skipping the write.

### AUDIT-33 — Time-zone change without an app launch zeroes the widget's finished total *(critic-found)*

- **Where:** `Widgets/PracticeWidget.swift:52`; `Packages/PianismCore/Sources/PianismCore/PracticeTotals.swift:32`
- **Evidence:** The widget calls `totals.today(at:in: .autoupdatingCurrent)`; the stored `day` is a start-of-day instant in the zone the app grouped by, but `today` compares in the widget's *current* zone. The file is only rewritten on app foreground refresh.
- **Impact:** After travelling across a time-zone boundary the widget shows 0 finished minutes for a day that has practice, until the app is opened. The app itself is correct on next foreground — glance-only defect.
- **Fix:** Store the grouping time-zone identifier (or the day as a calendar date) in `PracticeTotals` and compare in that zone, or fall back to the most recent totals when the stored day is within ~36 hours.

### AUDIT-34 — Live Activity is never marked stale

- **Where:** `App/SystemPracticeGlance.swift:93`
- **Evidence:** `ActivityContent(state:…, staleDate: nil)` always; reconcile treats `.stale` as live/showing (`:100`). Critic re-confirmed.
- **Impact:** A session paused overnight keeps a fresh-looking Lock Screen activity past ActivityKit's 8-hour limit instead of dimming as stale.
- **Fix:** Pass `staleDate` as the earlier of cap-reached time or session start + 8 h.

### AUDIT-35 — No foreground re-enumeration of MIDI sources

- **Where:** `Packages/PianismMIDI/Sources/PianismMIDI/CoreMIDINotes.swift:60`
- **Evidence:** `connectAll()` runs only from `init` and the CoreMIDI notify block; nothing on the scenePhase-active path (`RootView.swift:88`, `PianismApp.swift:260`) re-runs it.
- **Fix:** Expose an internal `refresh()` calling `connectAll()` and invoke it on scenePhase-active next to `practice.cameToFront()`.

### AUDIT-36 — Failed CoreMIDI setup leaves a zombie adapter

- **Where:** `Packages/PianismMIDI/Sources/PianismMIDI/CoreMIDINotes.swift:55`
- **Evidence:** On `status != noErr`, `init` logs and returns, leaving both streams unfinished with no retry and no user-visible state.
- **Fix:** On failure, finish both continuations (or record an unavailable flag the app can surface) and retry client/port creation on the next scenePhase-active.

### AUDIT-37 — Notification permission-denied path is silent, with no recovery

- **Where:** `Packages/PianismSystem/Sources/PianismSystem/UserNotificationNudges.swift:42`; `PracticeModel.swift:167`
- **Evidence:** `requestPermission()` discards the result (`_ = try? await …`); `askForNudges()` sets `canAskForNudges = false` *before* the answer, so after a denial the Remind-me button never returns and no Settings guidance exists. (A later Settings grant does self-heal, because refresh re-schedules.)
- **Fix:** Return the granted `Bool` from `requestPermission()`, keep a denied state in `PracticeModel`, and show a "Notifications are off — open Settings" row when `authorizationStatus == .denied`.

### AUDIT-38 — Serialized Task chain rebuilt on every `show()`; delegate thread assumption *(two Nits)*

- **Where:** `App/SystemPracticeGlance.swift:63`; `Packages/PianismSystem/Sources/PianismSystem/UserNotificationNudges.swift:99`
- **Evidence:** `show(_:cappedAt:)` unconditionally chains a new `Task` even when the `lastShown` guard (`:71`) then finds nothing changed — and `PracticeModel.refresh()` calls it on every tick. Separately, the notification delegate uses `MainActor.assumeIsolated` (`:107`) on the assumption of main-thread delivery.
- **Fix:** Early-return before creating the Task when session id/state/cap are unchanged (or use an actor serial queue). For the delegate: keep the completion-handler form, but guard with a runtime main-thread check and hop via `Task { @MainActor in … }` with `completionHandler` in a `defer` if device logs ever contradict the assumption.

## Minors — tests / CI / build

### AUDIT-39 — Test/CI hygiene cluster (fix as one `build`/`ci` PR or split)

| # | Where | Finding | Fix |
| --- | --- | --- | --- |
| a | `Makefile:82` | `-retry-tests-on-failure -test-iterations 2` masks flakes; flake analysis (`scripts/handover/flake-analyze.py`) never runs in CI | Upload per-iteration xcresult summaries; parse retried passes in CI and open/comment a tracking issue on retry |
| b | `AppUITests/UITestCase.swift:32` | Warm-up loops `app.launch` for up to 600 s dropping issues; `tearDown` waits 180 s in `kill` (`:68`) — a broken launch surfaces as a generic timeout after ~10 min | Cap warm-up at 120 s; attach the last launch error and fail the first test with that diagnostic |
| c | `Makefile:100` vs `ci.yml:48` | Lint scope/toolchain differ: Makefile lints `scripts`, CI does not; CI pins `swift:6.4.0-noble` while macOS jobs pick newest Xcode 27 | Share one `SWIFT_DIRS` list; pin the lint container to the Swift version in the selected Xcode |
| d | `scripts/fail-on-warnings.sh:15` | Touch-to-recompile runs only when `git merge-base HEAD origin/main` succeeds; detector (`:30`) matches only `file:line:column warning:` | Fall back to touching all Swift files; also match bare `warning:` (with an allowlist for tool noise) |
| e | `scripts/select-xcode.sh:6` | Highest `Xcode_[0-9.]+.app` by `sort -V` can be a symlink to a beta; empty result fails opaquely | Resolve symlinks, reject beta/RC per `xcodebuild -version`, fail with a clear message |
| f | `Pianism.xcscheme:23` | `codeCoverageEnabled YES` but coverage is never exported or gated | Export with `xcrun xccov` in the adapters job; fail when Glance/Features-models coverage drops below an agreed threshold |
| g | `AppUITests/PracticeTests.swift:1152` | Four e2e tests (Live Activity island, MIDI server, VoiceOver audit) run only nightly via `skipUnlessSoaking` | Move deterministic ones to PR runs with fixed-clock hooks; keep true real-time cases nightly with a weekly-pass promotion log |

---

## Disputed and dropped (do not "fix" these)

| Claim | Why it was dropped |
| --- | --- |
| *Blocker: production `aps-environment` is `development`* (`Config/Pianism.entitlements:24`) | The lines are real (entitlement hard-codes `development`; `Release.xcconfig:8` sets Production only for the CloudKit container environment), but no repo evidence proves the claimed failure: Xcode/provisioning may rewrite `aps-environment` at distribution signing, and no archive/ExportOptions/signed bundle exists in the repo to settle it. The persistence reviewer independently left this unresolved. **Downgraded to U-1 below.** Do not variable-ise the entitlement blind — that could itself break Development signing. |
| *Minor: WeekView title force-indexes `days[6]` — crash risk* (`WeekView.swift:130`) | Falsified: `PracticeWeek.init` (`PracticeWeek.swift:13`) unconditionally builds exactly seven days, and `HistoryModel.week` always constructs it that way. `days[0]`/`days[6]` cannot be out of bounds through any current call path. At most a style nit (`first`/`last`); not tracked. (AUDIT-11, the missing `#Preview`, stands.) |
| *Session `timeZoneID` stored but unused* | Intentional per ADR 0006 (*stored before anything uses it*). Not scored. |
| *No background MIDI* | Intentional: no audio/Bluetooth background mode; the screen is held on during MIDI sessions per MIDI-R5. Reported as context, not a defect. |

## Unresolved — needs evidence outside this repo pass

- **U-1 `aps-environment` in a signed build.** Dump a signed Release archive's entitlements (`codesign -d --entitlements`) before changing anything. If it still reads `development`, this becomes a Blocker: introduce `PIANISM_APS_ENVIRONMENT` in Debug/Release xcconfigs (`development`/`production`) and reference it from the entitlements. AUDIT-08's CI archive produces exactly the artefact needed.
- **U-2 Two-device CloudKit behaviour** (edit-vs-delete / edit-vs-edit merging, sign-out store removal) — explicitly deferred to device checks in ADR 0006/0008. This is AUDIT-02's acceptance run.
- **U-3 Widget / Live Activity on hardware.** All device-checklist W/L/P/B rows are still *Not run yet*, including time-zone-change and background-intent-launch behaviour behind AUDIT-05/AUDIT-33 and the cap/stale behaviour in AUDIT-34. Code-level findings stand; hardware confirmation is owed before TestFlight.
- **U-4 Suites not executed in this pass.** Only `PianismCore` was run (113 tests, green). Before acting on persistence/features findings, run `make test-features test-adapters` on `fea4df4` to establish the green baseline this report assumes.
- **U-5 `docs/plans/*` beyond `plan-syn1-live-refresh.md`** (877 lines, pre-implementation design docs) were inventoried, not audited line-by-line.

## Strengths worth preserving (no action — do not regress)

- **Core:** ADR 0007 crash-safe archiving — save-then-outbox fallback, store cleared only if it still holds the same session ID, duplicate archives keep one copy (`SessionRecorder.swift:153`). Calendar/DST-correct week/day math via `dateInterval(of: .weekOfYear)` + `startOfDay`, verified on Santiago/Los Angeles cases (`PracticeWeek.swift:18`). Clock discipline: the only `Date()` in core Sources is `SystemClock.now`; all ports `Sendable`, `Mutex`-guarded doubles, no force unwraps (`WallClock.swift:16`). MIDI silence deadlines are exact and replay-verified against Kawai CA59 fixtures F1–F12 (`MIDIDetector.swift:91`). Stored-format compatibility by construction — added fields are Optional/nil-when-empty (`PracticeSession.swift:46`).
- **Features:** Consistent `@MainActor @Observable` models; race-safe undo (`.task(id:)` with ID re-check before commit); scene-phase-aware deadline tasks instead of timers; all 106 user-facing strings in the String Catalog with `bundle: .module`; VoiceOver rows combined into one spoken element; History separates load-failure / empty / unshowable / not-syncing states; 2,133 lines of requirement-tagged view-model tests.
- **Persistence:** `@Attribute(.allowsCloudEncryption)` on note/tag-name/composer only (`HistorySchema.swift:22`); schema freeze snapshot-tested against `docs/cloudkit/schema-v1-fields.txt` (`HistoryStoreFormatTests.swift:103`); legacy JSON files still decode (`SessionFileFormatTests.swift:19`); deletion is a tombstone that erases user words and cannot be resurrected by a stale outbox copy (`SwiftDataSessionHistory.swift:80`); newer-version records refuse old-version writes (`:60`); running-session file is `NSFileCoordinator`-coordinated, atomic, file-protected, and stress-tested 8×100 (`FileRunningSessionStore.swift:92`); store-open failure is retryable, never cached-fatal (`HistoryStore.swift:96`).
- **Platform:** Network MIDI session excluded and hot-plug reconciled (`CoreMIDINotes.swift:77`); packet parsing cannot misread SysEx as Note On (`:112`); at most one pending nudge with a guaranteed-positive trigger (`UserNotificationNudges.swift:74`); Live Activity reconcile collapses duplicates/killed-app leftovers to one (`SystemPracticeGlance.swift:91`); widget/Live Activity clocks stop at the cap with no process running (`PracticeWidget.swift:101`); screen-on/battery monitoring scoped to MIDI-or-ready windows only (`RootView.swift:66`); minimal background surface — `remote-notification` only (`Config/Info.plist:7`).
- **Process:** Swift 6 + strict concurrency + warnings-as-errors everywhere with a `fail-on-warnings` backstop; Periphery pinned by SHA-256 and run `--strict`; least-privilege split entitlements; 299 Swift Testing tests + 45 UI tests on `ManualClock`/fixtures with exact assertions.

## Suggested sequencing for the receiving agent

1. **Baseline first (U-4):** `make test-features test-adapters` on `fea4df4`; record green/red before touching anything.
2. **Crash/data class:** AUDIT-03 → AUDIT-12/13/14 (one core PR each, probe cases become the tests), then AUDIT-15/16/17.
3. **Daily user-visible:** AUDIT-04, AUDIT-05, AUDIT-33, AUDIT-34 (widget/glance cluster — pair with AUDIT-10's new Glance tests so the fixes land with coverage).
4. **MIDI hardware story:** AUDIT-01 + AUDIT-35/36, then the M2/P5 device-checklist runs (U-3).
5. **Sync truth:** AUDIT-02's two-device run (U-2) → ADR 0006 update → AUDIT-27/30/31.
6. **Release path:** AUDIT-08 (archive CI) → settle U-1 from its artefact → AUDIT-09, AUDIT-06, AUDIT-07, AUDIT-39.
7. **Polish:** AUDIT-11, AUDIT-18…25, AUDIT-26, AUDIT-28/29, AUDIT-32, AUDIT-37/38.
