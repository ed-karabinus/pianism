# SET-1 (Settings): implementation plan

Written 2026-11-02 by an Opus 5.5 plan agent (read-only) against main at f17cc7f. Nothing was built or run.

Sources:
- Issue #50 and its three comments.
- #164, and the comments on #7 (SES-3) and #8 (SES-4).
- PR #144, which added the pairing sheet.
- The spec's SET-1, SES-3, SES-4, HIS-3 and MIDI-2 rows, and its MIDI table.
- ADR 0010, and the code named below.

Anything not verified is listed in §7.

## Short summary

- **Where settings live:** the app's own `UserDefaults.standard`, on this device only. Never the App Group: ADR 0010 has the widget read no settings, and the one value it needs, the cap, reaches it through the totals file (#164). This contradicts one line of the spec (Q3).
- **Who reads and writes them:** one `SettingsModel` in PianismFeatures is the only reader and writer of the new keys. `PianismApp.init` reads the stored values, then applies the `PIANISM_*` overrides exactly as today, for that launch only, never written back.
- **What a change does:** `PracticeModel`'s nudge, cap and MIDI timeouts become settable, and each change refreshes. So a change reaches the running session, the notification, the Live Activity and, with #164, the widget.
- **Five PRs, ~730 production lines in all,** each a slice a user can see:
  1. Settings tab, pairing moved in, overlap warning back on (~130).
  2. Nudge time and cap (~170).
  3. MIDI start count, pause and save timeouts (~100).
  4. The nudge's notification switch (~110).
  5. Daily reminder (~220).
- **Weekly goal:** it ships with HIS-3 (#46), the only code that uses it (~35 lines there).
- **Why PR 1 goes first:** it stores nothing new and needs only two layout answers. It also gives the overlap warning a way back; today it stays off until a reinstall.
- **Questions:** eleven, in §6. Q1–2 block PR 1, and Q3–6 block PR 2.

## 0. What SET-1 asks for

Issue #50, as written:

> As a practicer, I want to adjust how Pianism nudges, caps and detects my practice.
> - [ ] Nudge time (SES-3)
> - [ ] Automatic cap (SES-4)
> - [ ] MIDI timeouts
> - [ ] Weekly goal (HIS-3)
> - [ ] Daily reminder, off by default

The spec's row says the same: "Nudge time, cap, MIDI timeouts, weekly goal, daily reminder (off by default)". It is a Must, in M3. The spec's MIDI section adds: "Timings below are defaults the user can change in Settings."

Added since, in the issue's comments and elsewhere:

- **Overlap warning** (SES-5, decided 2026-10-17): "An Overlap warning toggle, on by default, bound to `@AppStorage("showsOverlapWarning")` … With no Settings screen, it's off for good until a reinstall, so this toggle is the way back." And: "An end-to-end test turns the warning off from the editor and back on from Settings." It stays on the device and isn't synced.
- **Nudge** (SES-3, decided 2026-10-18): "'Still practicing?' after, 30–240 minutes of practice time, default 90", and "A toggle for the nudge's notification, kept in step with iOS's permission."
  - #7 adds that after Don't Allow, "SET-1 can add a link to iOS Settings".
  - It also mentions an earlier sketch: "a gear on Practice opening a Settings sheet, with a picker every 30 min from 30 min up to the 4-hour cap".
- **MIDI start count** (audit, 2026-10-28): "the number of notes that start a session adjustable, 1–10 (default 3, within 10 s)".
- **Piano pairing** (PR #144, decided 2026-10-28): "The piano line on Practice opens 'Connect a piano' … it moves into Settings when SET-1 builds that screen". The no-piano line "stays, as the way into pairing until Settings exists". MIDI-2 still needs "connection status shows on the Practice screen".

The spec's numbers:

| Setting | Default | Range in the spec |
|---|---|---|
| Nudge (SES-3) | 90 min of practice | 30–240 min |
| Cap (SES-4) | 4 h of practice | none given, only "(setting)" |
| MIDI start | 3 notes within 10 s | 1–10 notes |
| MIDI pause after | 60 s of silence | 15–300 s |
| MIDI save after | 10 min of silence | 2–60 min |
| MIDI end time | last note + 5 s | fixed |
| MIDI minimum session | 1 min of playing | fixed |
| Weekly goal (HIS-3) | 3 days | none given |
| Daily reminder | off | P6 says "at most one reminder a day" |

Not part of SET-1, but bound for the same screen later: the analytics opt-out (#19, M3) and Restore Purchases (PRO-1, M4). Nothing is built for them now.

What the code does today:

- **Nudge and cap:** constants in `PianismApp.init` (lines 37–38).
- **MIDI timeouts:** the defaults of `MIDISettings()` (line 41).
- **Start count:** `MIDIDetector.startThreshold = 3`, a private constant with a fixed 10 s window.
- **Existing stored values:** `PracticeModel` already takes `defaults: UserDefaults` for the "Still practicing?" answer (`stillPracticingAnswered`). Two views use `@AppStorage`: `showsOverlapWarning` in SessionEditorView and `showsWeekByTag` in WeekView.
- **Pairing:** `ConnectPianoView` is a sheet, opened from Practice's piano line (`isConnectingPiano`, `practice.pianos`).
- **Navigation:** `RootView` is a `TabView` with two tabs, Practice and History.

## 1. Where settings live

### 1.1 Store

Settings go in `UserDefaults.standard`, the app's own domain. Not the App Group suite, and not synced.

- **Why not the App Group:** ADR 0010 says the extension only reads two files, and the GLN plan's SET-1 note says "the widget reads no settings". The only setting the extension needs, the cap, reaches it as a field of the totals file (#164), written by the app. The nudge, the MIDI timeouts, the goal and the reminder are all rules the app process applies.
- **Privacy manifest:** unchanged. Its CA92.1 entry ("read only by the app") still holds. An App Group suite would add 1C8F.1.
- **Tests:** `PIANISM_RESET=1` already removes the standard domain, so tests start from defaults with no new code.
- **The conflict:** this contradicts the spec's line "Settings live in UserDefaults inside the App Group so the widget can read them", and its 1C8F.1 privacy row (Q3).

### 1.2 Keys (permanent)

Rules for every key:

- **Names:** camelCase with no prefix, like the existing keys.
- **Units:** times are seconds, stored as `Double`, the unit of `TimeInterval` and of the `PIANISM_*` overrides.
- **Defaults:** a missing key means today's default. Defaults are never written, so if Ed changes a default later, it reaches everyone who never changed the setting.
- **Bad values:** a stored value outside the range, or between choices, reads as the nearest allowed choice. That lets a later build narrow a range safely.

| Key | Type | Default | Range (pending Ed) | PR |
|---|---|---|---|---|
| `showsOverlapWarning` | Bool | true | existing key, reused verbatim | 1 |
| `stillPracticingAfter` | Double, seconds | 5400 | 1800–14400 in 30-min steps, kept below the cap | 2 |
| `automaticCapAfter` | Double, seconds | 14400 | Q4 (recommended 1–8 h, whole hours) | 2 |
| `midiStartNotes` | Int | 3 | 1–10 | 3 |
| `midiPauseAfter` | Double, seconds | 60 | 15–300 | 3 |
| `midiSaveAfter` | Double, seconds | 600 | 120–3600 | 3 |
| `notifiesStillPracticing` | Bool | true | none | 4 |
| `remindsDaily` | Bool | false | none | 5 |
| `dailyReminderMinute` | Int, minutes after local midnight | Q9 | 0–1439 | 5 |
| `weeklyGoalDays` | Int | 3 | 1–7 | HIS-3 |

No migration is needed: nothing stored today holds a nudge, cap or MIDI value. `showsOverlapWarning` must keep its exact name. Renaming it would turn the warning back on for everyone who turned it off.

### 1.3 Code shape

- **Core, `PracticeSettings` (new, tested on Linux):**
  - It holds the nudge and cap defaults, their choices, and the "nearest allowed" rule.
  - It keeps the nudge below the cap: if a stored pair breaks that, the nudge drops to the largest choice below the cap.
- **Core, `MIDISettings`:**
  - It gains `startNotes` and the MIDI ranges.
  - `MIDIDetector` uses `startNotes` instead of its constant, and its `settings` becomes settable, so a change applies to the session being played.
  - `minimumPlayed`, the 10 s window and the 5 s tail stay fixed, as the spec says.
- **Features, `SettingsModel` (new, `@MainActor @Observable`, `init(defaults:practice:)`):**
  - It follows the pattern of `TagPickerModel(practice:library:)`, and is the only reader and writer of the keys above.
  - `static func stored(in:)` returns the values to launch with.
  - Each property reads the live value from `PracticeModel`; its setter writes the key and sets the value on `PracticeModel`.
  - No protocol: tests pass a suite-named `UserDefaults`, as `PracticeModelTests` already does.
- **`PracticeModel`:**
  - `let nudge` and `let cap` become `var` with an internal setter, and a MIDI setter updates the detector. Each change calls `refresh()`.
  - Its init keeps `nudge:cap:midi:`, so the ~25 existing test call sites don't change.
- **`RootView`:** the wake-up loop's `.task(id:)` keys on `practice.session` today. It must also key on the nudge, the cap and the MIDI timeouts; otherwise a changed nudge waits for the old deadline.
- **Cap banner:** `PracticeView.capBanner` says the session stopped at `model.cap`. After a change it would name the new cap, not the one that stopped the session. It should use the last session's practice time instead, which equals the cap that stopped it.

### 1.4 How `PianismApp.init` reads them, and how tests override them

The order matters, and it differs from today:

1. Parse the `PIANISM_*` overrides into optionals. Their names stay the same: `PIANISM_NUDGE_SECONDS`, `PIANISM_CAP_SECONDS`, `PIANISM_MIDI_PAUSE_SECONDS`, `PIANISM_MIDI_SAVE_SECONDS`, `PIANISM_MIDI_MINIMUM_SECONDS`.
2. Run `PIANISM_RESET=1`, which clears the domain. Stored values must be read after this; reading them before would pick up the previous test's settings.
3. Call `SettingsModel.stored(in: .standard)`.
4. Apply each override on top, for this launch only. Overrides are never written, and they bypass the ranges, since tests use 3 s, 12 s and 20 s.
5. Build `PracticeModel(… nudge:cap:midi:)`, then `SettingsModel(defaults: .standard, practice:)`, and pass it to `RootView`.

The precedence is: override, then stored value, then default. If a test with an override also changes that setting in Settings, the change wins from then on, as it would for a user. Every existing test that uses an override keeps working untouched, and that is the check.

### 1.5 A change while a session runs (recommended; Q6)

The change applies at once. `refresh()` does four things:

- **Notification:** it reschedules "Still practicing?" for the new nudge, or asks at once if practice is already past it.
- **Cap:** if the new cap is already reached, it ends the session at the moment practice reached it. The banner and Edit show, as SES-4 decided.
- **Live Activity:** it shows the session with the new cap, which moves the end of the activity's clock.
- **MIDI:** new timeouts move the detector's next deadline.

## 2. The screen and its entry point

Recommended: a third tab, "Settings" (`gearshape`), after History (Q1).

- **Practice stays as it is** (P1: one tap to start, the time always visible). No gear, no toolbar, and no NavigationStack, which would change the layout the text-size tests pin.
- **Pairing fits naturally:** the pairing page pushes inside the Settings tab's own NavigationStack, where Apple's Bluetooth screen already pushes today inside the sheet.
- **Little new plumbing:** the tab view exists. `AppTab` gains a case, and `keepsScreenAwake` still keys on Practice.
- **The alternative** is a gear on Practice opening a sheet, as #7's earlier sketch had it.

The sections once all five PRs are in (PR number in brackets):

- **Piano:**
  - "Connect a piano", or "MIDI KEYBOARD connected", which pushes the pairing page [1].
  - Notes that start a session; Pause after a silence of; Save after a silence of [3].
- **"Still practicing?"**:
  - Ask after [2].
  - Notify me when I'm away [4].
  - Stop a session left running after [2].
- **Reminder:** Daily reminder, with its time when it's on [5].
- **History:** Overlap warning [1]; Weekly goal [HIS-3].

`ConnectPianoView` loses its own NavigationStack and its Done button, since it is pushed now. Its previews wrap it in a NavigationStack.

For Practice's piano line (Q2), the recommendation is:

- Show plain "MIDI KEYBOARD connected" text when a piano is connected; that is MIDI-2's status requirement.
- Show nothing when none is connected, since Settings is now the way in. ONB-1's "Connect a keyboard" link will point there too.

## 3. The PR sequence

Production lines leave out tests, docs and the String Catalog, as CLAUDE.md counts them. The column with tests and strings keeps each review under ~500 lines. Branches are named `set-1-…`, and titles are `feat(SET-1): …`.

| # | Title | Production | With tests and strings | Blocked on |
|---|---|---|---|---|
| 1 | Add Settings, where a piano connects and the overlap warning comes back | ~130 | ~205 | Q1, Q2 |
| 2 | Set when Pianism asks "Still practicing?" and when it stops a session | ~170 | ~400 | Q3–Q6; best after #164 |
| 3 | Set how a piano starts, pauses and saves a session | ~100 | ~215 | Q7 |
| 4 | Turn the "Still practicing?" notification on and off in Settings | ~110 | ~255 | Q8 |
| 5 | Remind me to practice once a day | ~220 | ~440 | Q9, Q11 |
| HIS-3 | Weekly goal row, in HIS-3's PR | ~35 | n/a | Q10 |

Each PR after the first adds a section to `SettingsView` and properties to `SettingsModel`, so they have to land in order.

### PR 1 — `feat(SET-1): Add Settings, where a piano connects and the overlap warning comes back` (~130)

Files:

- **`Packages/PianismFeatures/Sources/PianismFeatures/Settings/SettingsView.swift`** (new, ~75):
  - A NavigationStack and a Form.
  - A Piano section, whose row pushes `ConnectPianoView(pianos:)`.
  - A History section: a `Toggle` on `@AppStorage(SettingsKey.showsOverlapWarning)`, with a footer.
  - Previews in light, dark and AX5.
- **`RootView.swift`** (~15): the Settings tab, `AppTab.settings`, and the IDs `settings.pianos` and `settings.overlap-warning`.
- **`ConnectPianoView.swift`** (−12, +6): drops its NavigationStack and Done button. The `pianosDone` ID goes.
- **`PracticeView.swift`** (−15, +8): the piano line, per Q2.
- **`SessionEditorView.swift`** (~2): reads the key from one shared constant.
- **`HistoryView.swift`** (1): "In Settings, sign in to iCloud" becomes "In the Settings app, …", now that the app has its own Settings. The end-to-end assertion at PracticeTests.swift:985 changes with it.
- **String Catalog:** about 8 strings.

What the user sees:

- A Settings tab.
- Under Piano: what's connected, how to connect a piano, and Apple's Bluetooth pairing screen.
- Under History: Overlap warning, which is on unless they tapped "Don't show again".
- Practice's piano line, as Q2 decides.

Tests (end to end). They all go in `PracticeTests.swift`, because its helpers are private and `scripts/handover/e2e-class.sh` names that class.

- **`testSettingsConnectsAPiano`** (new; MIDI-2):
  - Open Settings; the row reads "Connect a piano".
  - Tap it; `pianos.pair` and the replug tip show; go back.
  - With `midiPiano: "MIDI KEYBOARD"`, both the row and Practice read "MIDI KEYBOARD connected".
  - These steps come out of `testStartPauseResumeStop`. They are moved, not dropped, and the PR says so.
- **`testOverlapWarningCanBeTurnedOff`** (extended; SES-5, SET-1): after the relaunch shows no warning, turn Overlap warning on in Settings, add the overlapping session, and the warning shows. This is the test #50's comment asks for.
- **`testTheScreensPassTheAccessibilityAudit`:** audits "Settings", and "Connect a piano" as a pushed page. It is no longer a sheet, so the iPad sheet exemption no longer applies.
- **`testAPianoTheSystemAnnouncesIsHeard`** (nightly): its "Connect a piano" assertion follows Q2.
- **Helper:** `openSettings(_:)`, like `openHistory`.

There are no feature tests, because there is no model logic. In the device checklist, P4 and P5 now start from Settings › Piano.

### PR 2 — `feat(SET-1): Set when Pianism asks "Still practicing?" and when it stops a session` (~170)

Files:

- **Core, `PracticeSettings.swift`** (new, ~35): defaults, choices, the nearest-allowed rule, and the nudge kept below the cap (Q5).
- **Features:**
  - `Settings/SettingsModel.swift` (new, ~60).
  - `PracticeModel`: settable nudge and cap that refresh on change, and the cap banner taken from the session's time (~10).
  - `RootView`: the task id and the init (~8).
  - `SettingsView`: a section with two pickers and footers (~35).
  - `Previews.swift` (~10).
- **`App/PianismApp.swift`** (~12): the order in §1.4.
- **`SystemPracticeGlance`** (~3), only if #164 has merged and still writes only when the session's ID or state changed: it also rewrites and reloads when only the cap changed (§4).

What the user sees: "Ask 'Still practicing?' after 1 h 30 min" and "Stop a session left running after 4 hours", each a menu. Each picker offers only values that keep the nudge below the cap. A change shows at once on a running session, including the Lock Screen clock.

Tests:

- **Core, `PracticeSettingsTests`** (Linux):
  - "SET-1: nothing stored reads as 90 minutes and 4 hours"
  - "SET-1: a stored value outside its range or between steps reads as the nearest choice"
  - "SET-1, SES-3: the nudge's choices stop below the cap, and the cap's start above the nudge"
- **Features, `SettingsModelTests`** (`.serialized`, suite-named defaults):
  - "SET-1: a nudge and cap set in Settings are read back at the next launch"
  - "SET-1, SES-3: a new nudge reschedules the running session's notification, or asks at once if practice is past it" (checks `InMemoryNudges.pending` and `isAskingStillPracticing`)
  - "SET-1, SES-4: a new cap ends a session already past it at the moment it reached it, and shows the running session with the new cap" (checks `InMemoryPracticeGlance.shownCaps`)
  - "SET-1: after a change, the next wake-up is the new deadline" (checks `nextRefresh`)
  - "SES-4: the cap banner names the cap that stopped the session, not one set since"
- **End to end, `testTheNudgeAndCapComeFromSettings`** (fixed clock, reset):
  - In Settings, set the nudge to 30 min and the cap to 1 h (or Q4's smallest), then Start and kill the app.
  - Relaunch at +35 min: "Still practicing?" shows. Kill again.
  - Relaunch at +3 h: the banner says "at 1 hour of practice", and Settings still shows both values.
- **Existing tests:** `testSessionLeftRunningStopsAtTheCap` keeps proving the 4-hour default, and the override tests prove the `PIANISM_*` variables still work.
- **Mutation and device checks:** run `make mutate`. New device row: change the cap with a session running, then close the app. The Lock Screen clock, and the widget with #164, stop at the new cap.

### PR 3 — `feat(SET-1): Set how a piano starts, pauses and saves a session` (~100)

Files:

- **Core** (~20): `MIDISettings` gains `startNotes` and the ranges; `MIDIDetector` uses `startNotes`, and its settings become settable.
- **`PracticeModel`** (~6): the MIDI setter.
- **`SettingsModel`** (~30): three properties.
- **`SettingsView`** (~35): Piano rows, a Stepper for notes and menus for the two silences.
- **`PianismApp`** (~5).

What the user sees: under Piano, "Notes that start a session: 3", "Pause after a silence of 1 min" and "Save after a silence of 10 min".

Tests:

- **Core, `MIDIDetectorTests`:**
  - "MIDI-1, SET-1: the number of notes that start a session comes from the settings", run with 1, 3 and 10 notes; the 10 s window holds in each case.
  - "a pause changed while playing moves the deadline"
- **Features:** "SET-1: the MIDI settings are kept and reach the detector, so one note starts a session when set to 1"
- **End to end, `testOneNoteStartsASessionWhenSettingsSaySo`:** set notes to 1 in Settings, kill, relaunch with `midiNotes: "0"`: Practice reads "Practicing".
- **Mutation:** run `make mutate`.

### PR 4 — `feat(SET-1): Turn the "Still practicing?" notification on and off in Settings` (~110)

Files:

- **Core port** (~10): `PracticeNudges.canAskPermission()` becomes `permission() async -> NotificationPermission`, with cases `.notAsked`, `.denied` and `.allowed`.
- **The port's fakes** (~10): `InMemoryNudges`, `OfferingNudges` and `PreviewNudges`.
- **`UserNotificationNudges`** (~12): maps the system's permission status onto those cases.
- **`PracticeModel`** (~10): with the switch off, `refresh()` cancels instead of scheduling, and the banner doesn't offer "Remind me".
- **`SettingsModel`** (~35): the permission state, re-read when the app comes to the front.
- **`SettingsView`** (~30): the toggle, a footer, and "Open the Settings app" after Don't Allow (`UIApplication.openNotificationSettingsURLString`, iOS only).

What the user sees: "Notify me when I'm away", which reads on only while iOS allows it.

- Turning it on asks iOS the first time, or offers the Settings app after Don't Allow.
- With it off, nothing is scheduled, even though iOS allows notifications.

Tests:

- **Features:**
  - "SET-1, SES-3: with the notification off, no nudge waits and the banner doesn't offer it"
  - "SET-1: the switch reads on only while iOS allows notifications"
  - "SET-1: turning it on asks iOS when it hasn't asked"
- **Adapter, `UserNotificationNudgesTests`:** maps each status.
- **End to end, `testTheNudgeNotificationCanBeTurnedOff`** (real clock, nudge of 20 s by override):
  - Turn the switch off in Settings, Start, go Home: no notification for 30 s.
  - Turn it back on, tapping Allow if the system asks, as the existing test does.
  - A session left away then gets the notification.
  - The timing matches `testNotificationAsksStillPracticing`.

### PR 5 — `feat(SET-1): Remind me to practice once a day` (~220)

Files:

- **Core** (~55):
  - A rule for the next reminder dates: the chosen time each day, skipping a day already practiced if Q9 says so, and handling DST and midnight.
  - A port, `PracticeReminders { schedule(at:), cancel() }`, with a fake.
- **`PianismSystem`, `UserNotificationReminders`** (~50): calendar triggers, one identifier per day.
- **Features** (~40):
  - `SettingsModel` gets the switch and the time.
  - `HistoryModel.refresh()` re-plans the reminder after a session saves, where it already writes today's total.
- **`SettingsView`** (~30): the toggle, a `DatePicker` (hour and minute) when it's on, and a footer.
- **Wiring** (~15), including a Debug reset of pending reminders.
- **Previews** (~10).

What the user sees: "Daily reminder", off by default. Turned on, it asks iOS if needed and shows a time. A notification comes at that time each day, or each day not yet practiced; the wording is Q9.

Tests:

- **Core** (Linux): the dates at midnight, across DST, and when today was already practiced.
- **Adapter:** the notification requests it builds.
- **Features:**
  - "SET-1: the reminder is off by default and schedules nothing"
  - "turning it on schedules at the chosen time; turning it off cancels"
  - "a session saved today moves the reminder to tomorrow" (if Q9 says so)
- **End to end, `testTheDailyReminderIsOffUntilTurnedOn`:** off on a fresh install; on after Allow; the time shows; it is kept after a relaunch.
- **Arrival at the set time:** a nightly test (`skipUnlessSoaking`, reminder one real minute ahead) or device-checklist row R1.

### Weekly goal (with HIS-3, #46)

A Stepper from 1 to 7 days, default 3, stored under `weeklyGoalDays`. HIS-3's "weeks meeting your goal" reads it. It is built in HIS-3's PR so it has a user from day one; CLAUDE.md allows nothing without a caller. SET-1's checkbox is ticked when that PR merges (Q10).

## 4. How this fits #164

- **What #164 does:** it adds an optional `cap` to `PracticeTotals`, written "by the session-showing path rather than by History", so the widget's clock ends at `practiceOrigin + cap`. That path is `SystemPracticeGlance.show(_:cappedAt:)`, which `PracticeModel.refresh()` calls with `cappedAt: cap` for a timer session.
- **What SET-1 changes:** not the write itself. It changes where `cap` comes from (a setting instead of a constant) and makes each change call `refresh()`. So the app writes the current value from the same place, every time it shows the session.
- **The one thing that must hold:** the totals file must be rewritten, and the widget reloaded, when only the cap changed.
  - Today `show(_:cappedAt:)` reloads only when the session's ID or state changed, and `show(totals)` skips totals equal to the last ones.
  - #164 should compare the cap too. If it doesn't, PR 2 adds that (~3 lines).
- **Order:** #164 first, since it's small and approved, then PR 2. PR 2's features test (`shownCaps` after a change) and its device row then cover the whole chain. The other order works too: #164 would then read the setting's live value with no change.
- **ADR 0010 holds:** nothing in the extension reads a setting, and the nudge never reaches the extension.

## 5. Risks, and what's permanent

What's permanent:

- The key names, their types and units, and the rule that a missing key means the default (§1.2). Renaming later needs a migration.
- `showsOverlapWarning` keeps its name.
- Settings stay out of the App Group. Moving them in later means a one-time copy plus 1C8F.1, so the choice should be recorded now (Q3).
- Settings are per device, not synced. Adding iCloud key-value sync later is additive, but needs an entitlement.
- The daily reminder's notification identifiers stay in the system across app updates. Renaming them later leaves stray reminders behind.

Risks:

- **R1. Lowering the cap mid-session.** A cap below a running session's practice ends it, back-dated to the new cap, so an hour can vanish in one tap. The banner and Edit recover it. The alternative is locking both pickers while a timer session runs (Q6).
- **R2. A stale wake-up.** `RootView`'s loop sleeps until the old deadline unless its task id includes the settings (§1.3). The features test on `nextRefresh` covers this.
- **R3. The cap banner naming the wrong cap** (§1.3). ADR 0010's consequences mention a rule that a session archived at exactly the cap counts as capped. I didn't find it in the code. Any rule like that breaks once the cap can change between capping and showing, so keep `cappedID`.
- **R4. Launch order.** Reading stored values before `PIANISM_RESET` would leak the previous test's settings into a reset launch (§1.4).
- **R5. Pickers under XCUITest.** Menu pickers inside a Form on iOS 26 and 27 may need two taps, as the tab bar already did (#80). Give each picker an identifier, and retry the open as `openHistory` does.
- **R6. Notification permission in tests.** A simulator asks once per install, so the PR 4 and PR 5 end-to-end tests must pass whether or not the system asks, as `testNotificationAsksStillPracticing` does. No XCUITest API resets the notification permission.
- **R7. The cap's upper limit.** It must stay within a Live Activity's 8 hours, or the Lock Screen clock stops before the cap (Q4).
- **R8. "Settings" now means two things** in the app's copy (HistoryView's iCloud notice). PR 1 rewords it.
- **R9. Apple's Bluetooth pairing screen** is pushed from a tab's NavigationStack rather than a sheet. Rerun device check P4.
- **R10. The weekly goal per device.** An iPhone and an iPad may count "weeks meeting your goal" differently (Q10).

## 6. Questions for Ed

Blocking PR 1:

1. **Entry point:** a third tab, "Settings" (recommended), or a gear on Practice opening a sheet, as #7's earlier sketch had it?
2. **Practice's piano line** once pairing lives in Settings:
   - (a) plain "MIDI KEYBOARD connected" when a piano is connected, nothing when none (recommended);
   - (b) keep "Connect a piano", now switching to Settings › Piano;
   - (c) keep the sheet as well.

Blocking PR 2:

3. **Store:** the app's own defaults, on this device, not synced and not in the App Group (recommended, per ADR 0010)? This contradicts the spec's "Settings live in UserDefaults inside the App Group so the widget can read them" and its 1C8F.1 privacy row. Will you amend the spec? And should the PR add a dated "Amended" note to ADR 0010 rather than a new ADR?
4. **The cap's range and steps:** the spec gives none. Recommended: 1–8 hours in whole hours, since 8 h is a Live Activity's limit.
5. **Nudge versus cap:** should each picker offer only values that keep the nudge below the cap, so neither changes the other (recommended)? Or may they meet, meaning "never ask"?
6. **A change during a running session:** apply it at once (recommended; a cap below the session's practice ends it, back-dated)? Or lock both pickers until the session ends?

Later PRs:

7. **MIDI steps:**
   - Are these the right choices? Notes 1–10 on a stepper; pause 15, 30, 45, 60, 90, 120, 180, 240 or 300 s; save 2, 5, 10, 15, 20, 30, 45 or 60 min.
   - Do the 10 s window, the 5 s tail and the 1-minute minimum stay fixed?
   - Are these settings shown to everyone (recommended), or only once a piano has connected?
8. **"Kept in step with iOS's permission":** which of these?
   - (a) An in-app switch, on by default (recommended). It reads on only while iOS allows notifications. Turning it on asks iOS or opens the Settings app, and turning it off stops Pianism's nudges.
   - (b) A status row that mirrors iOS's setting, with a link and no in-app off.
9. **Daily reminder:**
   - What's the default time (18:00?)?
   - Every day, or chosen weekdays?
   - Should it skip a day already practiced (recommended, per P6)?
   - What should it say?
   - Should it ask for permission when it's turned on (recommended)?
10. **Weekly goal:** ship it with HIS-3 (recommended), 1–7 days, default 3? Keep it on this device only like the rest, so two devices could disagree, or sync it?
11. **Scope:** must SET-1 close with the reminder (PR 5) in M3? Or may the reminder become its own issue, so SET-1 closes after PR 4 and HIS-3?

Decisions I took without asking (say if you disagree):

- The key names and units in §1.2, and that a missing key means the default.
- Overrides win for their launch and are never written.
- The Settings tests stay in `PracticeTests.swift`.
- A `SettingsModel` separate from `PracticeModel`.
- "In the Settings app" in the iCloud notice.
- Analytics (#19) and Restore Purchases (PRO-1) get their rows when they land, with nothing built for them now.

## 7. Not verified

- Nothing was built or run. The line counts come from reading main.
- How menu pickers and steppers behave under XCUITest on iOS 26 and 27 (R5).
- That `CABTMIDICentralViewController` behaves the same pushed from a tab as from a sheet (R9).
- Whether #164's implementation reloads the widget on a cap-only change (§4).
- That `Picker` and `Stepper` inside a Form pass the accessibility audit's hit-region check at default sizes.

### Critical files for implementation

- /Users/edward_karabinus/Developer/Pianism/App/PianismApp.swift — the read order: overrides, then `PIANISM_RESET`, then stored values, then overrides applied; and making `SettingsModel`.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeModel.swift — settable nudge, cap and MIDI timeouts that refresh on change; the cap banner's value.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/RootView.swift — the Settings tab, the wake-up task id, the accessibility IDs.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/Practice/ConnectPianoView.swift and PracticeView.swift — the pairing move and the piano line.
- /Users/edward_karabinus/Developer/Pianism/AppUITests/PracticeTests.swift — all the end-to-end tests and the `launch` helper with its `PIANISM_*` variables.
- /Users/edward_karabinus/Developer/Pianism/App/SystemPracticeGlance.swift — where #164 writes the cap, which must also reload on a cap-only change.
## 8. Decided with Ed, 2026-11-02 (picker), after a Fable check of this plan

- Q1: a third "Settings" tab. Q2: Practice's piano line shows status only ("<piano> connected", nothing when none). Q4: cap 1–8 h in whole hours, default 4. Q6: the cap row is locked while a timer session runs (with a footnote); a nudge change applies at once.
- "I approve the key table and defaults": the §1.2 keys, seconds, unset key = default; nudge always below the cap; MIDI ranges per spec, shown to everyone; notification switch is an in-app toggle (Q8 a); weekly goal ships with HIS-3, per device. Settings in UserDefaults.standard (Q3).
- Spec: ONE-TIME authorization to amend exactly two lines with SET-1's first settings PR: "Settings live in UserDefaults inside the App Group so the widget can read them" and the privacy row listing the widget target with 1C8F.1. ADR 0010 needs no amendment.
- Q9: reminder default 6:00 PM, every day but skipping a day already practiced, asks permission when turned on; wording drafted in the PR for Ed. Q11: the reminder stays in SET-1 (closes after all five PRs).
- Fable check changes to apply: (1) no SettingsModel in PR 2: PracticeModel reads/writes its own keys (it already takes `defaults:` and is built after PIANISM_RESET); SettingsView binds with @Bindable; a SettingsModel only if PR 4 needs it. (2) R1 and the "cap that stopped it" test go with the cap lock; keep the banner using the session's time. (3) R3 is unfounded: `cappedID` is by ID. (4) §4 is done by #168. (6) Drop "nearest allowed choice" (the picker is the only writer); one repeating trigger unless skipping practiced days needs per-day requests (it does, per Q9); no PracticeSettings type in Core unless the nudge-below-cap rule needs it. (7) RootView's wake-up `.task(id:)` keys on `practice.nextRefresh`. (10) Audit test waits on `pianos.pair` not `pianos.done`; keep a named iPad/iOS 26 skip ready; Steppers fail the 44 pt hit region, so use menu Pickers for notes and the weekly goal; budget a retrying helper for Toggle/Picker taps. Ask Ed to approve removing the sheet's Done (UI test change): covered by Q1, as pairing becomes a pushed page.
