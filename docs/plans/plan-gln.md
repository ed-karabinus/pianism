# GLN-2 (small widget) and GLN-1 (Live Activity): implementation plan

Written 2026-10-30 by a Fable 5.1 plan agent (read-only) against main at 9593c1c and the spike branch `spike-17-widget-live-activity` (4962ea5). Nothing was built or run. Where it could not verify something, it is listed under "Not verified" and "Risks".

## Short summary

- Recommended shape: one WidgetKit extension target (`PianismWidgets`) hosting both the small widget and the Live Activity; a tiny iOS-only package `Packages/PianismGlance` for the types the app and the extension must both name (Live Activity attributes, the four `LiveActivityIntent`s, the commands they call, the widget kind and App Group constants); the ActivityKit/WidgetKit adapter in `App/` (it is iOS-only and untestable off-device); a new core port `PracticeGlance` that `PracticeModel` and `HistoryModel` call; a totals file in the App Group written by the app (ADR 0004 already decided this) and read by the widget. The extension never writes: every change from the widget or the Live Activity runs in the app's process as a `LiveActivityIntent` and goes through `PracticeModel`, so the nudge, the cap and the archive path are the same code as a tap on Practice. This amends ADR 0003's table (which assumed the widget's Start writes from the extension).
- The spike (#17) proved the two load-bearing facts: a `LiveActivityIntent` runs in the app's process without opening the app, also after a force quit, and the extension target wires into the thin project with local packages on the first try. Its pbxproj diff, xcconfig, Info.plist, Live Activity view shape and 2-minute manual check are reusable; its intent body (writes the file itself, hard-coded App Group, fails the session when the activity can't start), its `Shared/` folder and its SpringBoard UI test are not.
- Four PRs: ADR (docs) → widget extension + today's total (~325 production lines + ~130 pbxproj) → Start from the widget (~150) → Live Activity (~280). Each shippable. Automated coverage: core on Linux, HistoryModel/PracticeModel on macOS, the totals file adapter on macOS, and a Debug launch hook (`PIANISM_INTENT=start|pause|resume|stop`) so end-to-end tests drive the same in-process intent path the widget and Live Activity use. Tapping a widget and seeing the Live Activity stay device checks (the spike showed SpringBoard automation stalls).
- Biggest unknown (retire first, half a day): App Intents declared in a static Swift package get their metadata extracted into both bundles with Xcode 27 (`AppIntentsPackage`). Fallback is the spike's `Shared/` folder.
- Owner questions in §7 (5), each changing the work.

## 0. What the spike proved, and what of it is reusable

Proved on the owner's iPhone 18 Pro (2026-10-16, issue #17 and `docs/spikes/17-widget-live-activity.md` on the spike branch):

1. A `LiveActivityIntent` named by a widget's `Button(intent:)` runs **in the app's process without opening the app**, including after the app was swiped away. The system launched the app in the background, the intent wrote the running-session file through `SessionRecorder` + `FileRunningSessionStore(appGroup:)`, and `Activity.request` started the Live Activity. Practice showed the session when the app was opened.
2. A widget extension target fits the thin project: a `PBXFileSystemSynchronizedRootGroup`, settings in an xcconfig, local package products linked, both targets building clean for the simulator on the first try.
3. The widget renders in the gallery; the Lock Screen and Dynamic Island showed a running `Text(timerInterval:)` clock.
4. Home Screen automation through `XCUIApplication(bundleIdentifier: "com.apple.springboard")` is unusable on the iOS 27 simulator: each tap's interruption check snapshots SpringBoard's whole tree, ~17 minutes, three times. So widget taps are device checks.
5. The Dynamic Island's compact clock sat off-centre: `Text(timerInterval:)` reserves its widest width and left-aligns.

Not tried by the spike: Live Activities turned off in Settings.

Reusable, as is or nearly:
- `Pianism.xcodeproj/project.pbxproj` diff (+131 lines): the `PianismWidgets` native target (`com.apple.product-type.app-extension`), its synchronized folder, Frameworks phase with package products, the app's "Embed Foundation Extensions" copy phase (`dstSubfolderSpec = 13`), the target dependency, the `Widgets.xcconfig` config list. Drop the `Shared` group.
- `Config/Widgets.xcconfig` (change `CODE_SIGN_ENTITLEMENTS` to a new `Config/Widgets.entitlements`, add `ENABLE_PREVIEWS = YES`), `Config/Widgets-Info.plist`, and `INFOPLIST_KEY_NSSupportsLiveActivities = YES` in `Config/App.xcconfig`.
- The shape of `Widgets/PianismWidgets.swift`: `WidgetBundle`, `StaticConfiguration` + `Button(intent:)`, `ActivityConfiguration` with `DynamicIslandExpandedRegion`s, `compactLeading/compactTrailing/minimal`.
- The 2-minute manual check, as the seed of the device-checklist rows.
- Its list "What the real implementation should do" (points 1 to 8): all adopted below, except point 1's `Shared/` folder, which becomes a package (fallback: the folder).

Not reusable: `Shared/StartPracticeIntent.swift` (writes the file itself with `SystemClock()` and a literal App Group, throws `SpikeError` after the session has started when the activity can't start, which violates "never fail a session because of its Live Activity"); `PracticeAttributes` with only `startedAt` (no session ID, no pause, no cap); `StartProvider` (`.now`, `.never`); `AppUITests/WidgetSpikeTests.swift`; the app icon commits (separate concern; not part of this plan).

## 1. Target and module layout

### 1.1 Targets

One new target, `PianismWidgets` (WidgetKit extension, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`), embedded in `Pianism.app`. It hosts both the small widget and the Live Activity: a Live Activity's `ActivityConfiguration` must live in a widget extension, and Apple's samples use one extension for both. No second extension, no intents extension.

Bundle ID `com.edkarabinus.Pianism.Widgets` (as the spike; automatic signing registered it under the owner's team on 2026-10-16).

### 1.2 Code placement (minimal; nothing "for later")

```
Widgets/                              synchronized folder, extension target only (add files on disk)
  PianismWidgets.swift                @main WidgetBundle: PracticeWidget(), PracticeLiveActivity()   [PR 2, PR 4]
  PracticeWidget.swift                StaticConfiguration(kind: PracticeWidget.kind), .systemSmall only,
                                      TimelineProvider + entry + view + #Previews                    [PR 2, grows in PR 3]
  PracticeLiveActivity.swift          ActivityConfiguration(for: PracticeAttributes.self): Lock Screen,
                                      Dynamic Island, #Previews                                      [PR 4]
  Localizable.xcstrings               the extension's user-facing strings (String Catalog)
Config/Widgets.xcconfig               PRODUCT_NAME, bundle ID, CODE_SIGN_ENTITLEMENTS = Config/Widgets.entitlements,
                                      GENERATE_INFOPLIST_FILE, INFOPLIST_FILE = Config/Widgets-Info.plist,
                                      INFOPLIST_KEY_CFBundleDisplayName = Pianism, SKIP_INSTALL = YES,
                                      APPLICATION_EXTENSION_API_ONLY = YES, ENABLE_PREVIEWS = YES,
                                      LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks @executable_path/../../Frameworks
Config/Widgets.entitlements           App Group only (least privilege; the spike reused Pianism.entitlements, which
                                      would give the extension iCloud and push entitlements it never uses)
Config/Widgets-Info.plist             the NSExtension dictionary (as the spike)
Config/App.xcconfig                   + INFOPLIST_KEY_NSSupportsLiveActivities = YES                   [PR 4]
Config/Shared.xcconfig                MARKETING_VERSION and CURRENT_PROJECT_VERSION move here from App.xcconfig,
                                      so the app and extension can never disagree (App Store validation requires equal versions)
Packages/PianismGlance/               NEW package, iOS only (platforms: [.iOS(.v26)]), depends on PianismCore only.
                                      What the app and the extension must both name:
  Sources/PianismGlance/
    AppGroup.swift                    public enum AppGroup { static let identifier = "group.com.edkarabinus.Pianism" }
                                      (replaces PianismApp.appGroup; "must match Config/*.entitlements")        [PR 2]
    PracticeWidgetKind.swift          the widget kind string the app reloads and the extension registers    [PR 2]
    GlanceCommands.swift              struct of @MainActor @Sendable async closures start/pause/resume/stop,
                                      registered by the app with AppDependencyManager                       [PR 3]
    PracticeIntents.swift             StartPracticeIntent [PR 3]; PausePracticeIntent, ResumePracticeIntent,
                                      StopPracticeIntent [PR 4]: LiveActivityIntent, @AppDependency var commands,
                                      isDiscoverable = false; plus the AppIntentsPackage conformance
    PracticeAttributes.swift          ActivityAttributes { sessionID } + ContentState { timer: ClosedRange<Date>,
                                      pausedAt: Date? } + init(session:cappedAt:)                           [PR 4]
    Resources/Localizable.xcstrings   the intents' titles
App/SystemPracticeGlance.swift        the PracticeGlance adapter: WidgetCenter reloads + FilePracticeTotals [PR 2],
                                      ActivityKit reconcile/request/update/end + settle() [PR 4]. In App/, not a
                                      package: ActivityKit and LiveActivityIntent are @available(macOS, unavailable)
                                      (checked in the Xcode 27.1 SDK), so it can never run under make test-adapters
                                      or make mutate; the app is its only caller (CLAUDE.md allows that, as with PianismMIDI)
Packages/PianismCore                  PracticeTotals + today rule [PR 2]; PracticeGlance port [PR 2, 3, 4];
                                      PracticeSession.practiceOrigin [PR 3]
Packages/PianismCoreTestSupport       InMemoryPracticeGlance
Packages/PianismPersistence           FilePracticeTotals (App Group JSON, atomic, protection until first unlock) [PR 2]
Packages/PianismFeatures              HistoryModel writes totals on refresh [PR 2]; PracticeModel shows the session
                                      on refresh, start/pause/resume/stop become public, perform caps first [PR 3, 4]
App/PianismApp.swift                  wires SystemPracticeGlance into both models, registers GlanceCommands,
                                      declares the AppIntentsPackage, Debug hook PIANISM_INTENT             [PR 2, 3, 4]
Makefile                              SWIFT_DIRS += Widgets; .github/workflows/ci.yml lint paths += Widgets   [PR 2]
README.md                             architecture diagram: "Widget extension → PianismGlance, Persistence, Core"
                                      (today it says "→ features"; the extension must not link PianismFeatures:
                                      RootView.swift:61 uses UIApplication.shared, which is unavailable in
                                      extensions and would fail the APPLICATION_EXTENSION_API_ONLY build)
docs/adr/0010-...md                   [PR 1]; docs/device-checklist.md rows [PR 3, PR 4]
```

Why a package for the shared types rather than the spike's `Shared/` folder: a compiler-enforced boundary (PianismGlance can't import PianismFeatures, so the intents can't bypass the commands seam), `make lint` and Periphery already cover `Packages/`, and ADR 0002 says code lives in packages. Why not everything in the package: the ActivityKit adapter can't be built for macOS, so a package holding it would be the first package with no tests and no mutation run; keeping it in `App/` says that plainly. Why the extension links PianismCore and PianismPersistence: it reads two App Group files through `FileRunningSessionStore` and `FilePracticeTotals`. It never links PianismFeatures, PianismSystem or PianismMIDI.

### 1.3 ADR

Yes, one new record, PR 1: **ADR 0010, "A widget extension shows practice outside the app; the App Group is the boundary and the app's model is the only writer."** It must:
- Record the target and the package, and why the adapter lives in `App/` (macOS unavailability; no `make mutate` coverage; what covers it instead: build, previews, the `PIANISM_INTENT` end-to-end tests, the device checklist).
- Amend ADR 0003's table: "Small widget's Start button: widget extension" becomes "app, launched in the background by a `LiveActivityIntent`"; Live Activity buttons likewise. The extension only reads. `NSFileCoordinator` stays (one writer process now, but a reader in another process, and it costs nothing).
- Amend ADR 0004's summary-file sentence: the file holds the day being practiced (today), not seven days; the widget adds the running session itself. (Small widget only; nothing reads a week.)
- State what is accepted: no new background mode (NFR-9 keeps `remote-notification` as the only one); a cap reached while no process runs is applied at the next run; widget buttons need an unlocked phone (Apple); a Live Activity lasts at most 8 h.
- Note the fallback if R1 (below) fails: intents compiled from a `Shared/` synchronized folder into both targets.

## 2. Start from the widget without opening the app

Path: `Button(intent: StartPracticeIntent())` in `PracticeWidget` → the system launches `Pianism.app` in the background (no scene) or uses the running process → `PianismApp.init()` runs as on any launch and, after making `practice`, registers `AppDependencyManager.shared.add(dependency: GlanceCommands(start: { practice.start(); await glance.settle() }, ...))` → `StartPracticeIntent.perform()` (`@MainActor`) reads `@AppDependency var commands: GlanceCommands` and calls `commands.start()` → `PracticeModel.start()` → `SessionRecorder.start()` writes `running-session.json` through `FileRunningSessionStore` → `refresh()` → `glance.show(session, cappedAt:)` (widget reload now; Live Activity from PR 4) and `nudges.schedule(...)`.

`AppDependencyManager.add` requires `Dependency: Sendable`; a struct of `@Sendable` closures satisfies it. The wrapper in the Xcode 27.1 SDK is `@AppDependency` (`AppDependency<Value>` where `Value: Sendable`). This is the pattern of Apple's "Accelerating app interactions with App Intents" sample (dependencies registered in the App's `init`); say so in the PR. The commands struct mirrors how `UserNotificationNudges(answered:opened:)` reaches the model today, instead of linking PianismFeatures into the extension.

Why the intent never writes the file itself (unlike the spike): with the model in the loop, Start from the widget is the same code as a tap, so it gets:
- **The "Still practicing?" nudge (SES-3):** `refresh()` schedules the notification through `UserNotificationNudges`, which `PianismApp.init` created before the model, so the category is registered. It fires at the nudge whether or not the app runs, if notifications were allowed. If they were never allowed, nothing asks until the app is opened, exactly as today for a session running with the app closed. The Live Activity does not ask (not in scope).
- **The cap (SES-4):** honestly, no process runs at the cap moment. The session is ended at the cap retroactively on the next `refresh()` (app launch or foreground, or the next intent) by `SessionRecorder.end(atCap:)`. PR 4 adds one rule so a Pause or Stop tapped after the cap caps instead of pausing: `PracticeModel.perform(_:)` calls `recorder.end(atCap: cap)` before the command (today `refresh()` does it only after, and `whenPracticeReaches` returns nil for a paused session, so a late Pause would keep 4 h 30 min). On a fresh background launch the model's `init` → `cameToFront()` → `refresh()` already caps before `perform()` runs; the new rule covers a process that was merely suspended with a stale model.
- **MIDI auto-detection (MIDI-1):** foreground only, as ADR 0003's table already says: `CoreMIDINotes` is consumed by `.task` modifiers in `RootView`, which exist only while a scene is connected. A widget-started session is `source: .timer`, so notes on it only answer the nudge (MIDI-R4). Nothing changes; the plan says so rather than promising detection.
- **Archive and outbox (ADR 0007):** unchanged, since `refresh()` runs `archive(to:or:)` in the app process.

How the app picks it up when it opens: nothing new. `RootView.onChange(of: scenePhase)` → `practice.cameToFront()` → `refresh()` → `recorder.current()` reads the file; `PracticeView.onAppear` → `refresh()`. If the app is already in the foreground when the widget is tapped, the intent runs in that process against the live `PracticeModel`, so Observation updates the screen (this retires the spike's point 4 with no file watching).

If a session is already running, `start()` throws `RecorderError.alreadyStarted`, which `perform` logs as superseded and refreshes; harmless. The widget hides Start while a session runs (see §4), so this is a race only.

Settings (SET-1 note): the widget reads no settings. The nudge and cap live where the intents run, in the app process (`PianismApp.init`'s `nudge` and `cap`), so when SET-1 makes them settings nothing in the extension changes.

Widget buttons don't work while the phone is locked (Apple); device-checklist row, and the ADR records it.

## 3. The Live Activity (PR 4)

### 3.1 Data

```swift
public struct PracticeAttributes: ActivityAttributes {
    public let sessionID: UUID                      // to reconcile with the stored session after a relaunch
    public struct ContentState: Codable, Hashable {
        public let timer: ClosedRange<Date>         // from when the practice time was zero to when it reaches the cap
        public let pausedAt: Date?                  // while paused, the moment the clock stopped
    }
}
```
Built by `ContentState(session:cappedAt:)` from two core facts: `session.practiceOrigin` (new in PR 3: `latestEvent - elapsed(at: latestEvent)`, nil once ended; Linux-tested) and the cap: `origin...(cap.map { origin + $0 } ?? .distantFuture)`; `pausedAt = session.state == .paused ? session.latestEvent : nil`. `PracticeModel` passes `cappedAt: timerSession == nil ? nil : cap`, so the "MIDI sessions aren't capped" rule stays in the model (it already has `timerSession`). Well under ActivityKit's 4 KB.

### 3.2 Showing time without pushes

`Text(timerInterval: state.timer, pauseTime: state.pausedAt, countsDown: false)` (the `pauseTime:` form exists in SwiftUICore in the iOS 26 SDK; checked). The system counts; no updates are sent while running. The clock stops by itself at `timer.upperBound`, which is the cap moment (`whenPracticeReaches(cap)` for a running session), so a session left running with the app killed shows 4:00:00 frozen, the frozen state the issue 47 comment asks for. `staleDate: timer.upperBound` marks it stale too. In the compact Dynamic Island, give it a fixed `.frame(width:)` with `.monospacedDigit()` and trailing alignment (the spike's off-centre finding; check in Xcode's Live Activity previews, then on the device).

### 3.3 Start, update, end: one idempotent `show`

`SystemPracticeGlance.show(_ session: PracticeSession?, cappedAt:)` is called from every `PracticeModel.refresh()` and reconciles ActivityKit with the stored session each time:
1. For each `Activity<PracticeAttributes>.activities`: if `attributes.sessionID == session?.id` and the session hasn't ended, `update` it if its `ContentState` differs; otherwise `end(nil, dismissalPolicy: .immediate)`.
2. If the session is running or paused and no activity matched: `Activity.request(attributes:content:)`, only when `ActivityAuthorizationInfo().areActivitiesEnabled`; a thrown error is logged at info and ignored. The session never fails because of its activity (spike point 5).
3. Reload the widget's timeline when the session's state or ID changed since the last `show`.

That one function covers: start (in app or from the widget), pause/resume (update with `pausedAt`), stop in the app, stop from the activity, the cap (the session reads as ended after `end(atCap:)` → ended), a MIDI session ended by a silence, and the **app-killed case** (on relaunch, `PracticeModel.init` → `refresh()` → `show` finds the system's surviving activity and updates or ends it; an activity for a session no longer in the file is ended). Only the app ever starts or ends an activity; the extension only renders.

Dismissal: `.immediate` everywhere; Practice shows "Last session: 25:03" and History the session. (`.default` would leave the final time on the Lock Screen for up to 4 h; that needs an "ended" look and a flag, so it is left out unless the owner wants it.)

Async: `request` is synchronous; `update`/`end` are `async`. The adapter queues them on one serial task chain and exposes `settle() async`. `GlanceCommands` closures end with `await glance.settle()` so an intent's `perform()` returns only after ActivityKit has taken the change; otherwise the system may suspend the background-launched app before the update lands. The port stays synchronous for the model.

### 3.4 Buttons

Lock Screen and expanded Dynamic Island: Pause ⇄ Resume (by `pausedAt`) and Stop as `Button(intent:)` with `Label` + `accessibilityLabel`. Compact and minimal islands: a `pianokeys` symbol and the clock; no room for buttons (Apple). Each intent calls `commands.pause()` / `resume()` / `stop()` → `PracticeModel`, so Stop on a MIDI session takes the detector path (`apply(detector.handle(.stop(now)))`) and a Pause past the nudge answers "Still practicing?" (`answerIfPastNudge`), as in the app. Strings in `Widgets/Localizable.xcstrings`.

Known limit to write down: while the app is away, nobody hears a MIDI silence, so a MIDI session's Live Activity keeps counting until the app next ticks, then drops back to the last note (ADR 0009's drop-back). The app can't hear notes while away either, so nothing is lost.

## 4. Today's total in the widget

Recommendation: **the app writes a small totals file to the App Group; the widget never opens the SwiftData store.** ADR 0004 already decided this ("The store belongs to the app process. The widget doesn't open it."). The alternative, opening `History.store` from the extension, is not even possible without moving the store out of `Application Support/[Debug/]History/` into the App Group container (a persistent location change needing migration, an ADR 0008-style check and two processes on one CloudKit-mirrored store), and the 30 MB extension budget argues against loading SwiftData+CloudKit there. Trade-off accepted: the file is a second copy that can go stale while the app is closed (a session synced from another device shows in the widget only after the app next opens; the app's own saves are always current because the app writes on every history change).

Pieces:
- Core `PracticeTotals` (Codable, Sendable): `day: Date` (the day's start, from `PracticeDay`) and `finished: TimeInterval`; `func today(at now: Date, running: PracticeSession?, in calendar: Calendar) -> TimeInterval` adds the running session's `elapsed(at: now)` only if it started on `now`'s day (sessions count toward the day they started, ADR 0004). Linux tests: midnight boundary, a session past midnight, a running session from yesterday, DST days.
- `HistoryModel.refresh()`: after `days` is built (waiting sessions included, pending deletion excluded), `glance.show(PracticeTotals(from: days, at: now, in: calendar))`, skipped when `loadFailed` so a History outage can't zero the widget. `HistoryModel.init` gains `glance: any PracticeGlance`.
- `FilePracticeTotals` (PianismPersistence): `<App Group>/practice-totals.json`, `write(_:)` atomic with `.completeFileProtectionUntilFirstUserAuthentication`, `read()` returning nil for a missing or unreadable file (logged). Tests on macOS plus a format sample test like `SessionFileFormatTests` (a build must read what the previous build wrote; a wrong read only costs a 0 until the app next writes, so no "unreadable" sidecar).
- `SystemPracticeGlance.show(totals:)`: write only if different from the last written, then `WidgetCenter.shared.reloadTimelines(ofKind: PracticeWidget.kind)`.
- The widget's `TimelineProvider`: reads `FileRunningSessionStore(appGroup:)?.current()` and `FilePracticeTotals(appGroup:)?.read()`, makes two entries, now and the next local midnight (`Calendar.autoupdatingCurrent`), policy `.atEnd`. The provider is the extension's composition root, so `Date()` there is the clock (E3); the rule it feeds is the core function above.
- The view: no session → "Today 25 min" (`Duration.formatted(.units(...))`; `ElapsedTime` is internal to PianismFeatures and the extension doesn't link it) and the Start button. Running or paused session (PR 3) → "Practicing"/"Paused" and a live total: `Text(timerInterval: (practiceOrigin - finishedToday)...distantFuture, pauseTime:, countsDown: false)`, Start hidden. VoiceOver labels on the button and the total.

Refresh policy: reloads come from the app process at the moments the numbers change (`show(session)` after every session change; `show(totals)` after every history change, including iCloud imports while the app is open and edits/deletes in History), plus the midnight entry. A handful per day, well inside WidgetKit's budget. Nothing runs at midnight while the app is closed, and nothing needs to: the midnight entry already shows 0 for the new day.

Time zone: the file's `day` is keyed in the app's calendar at write time; after a zone change the widget may show 0 until the app next writes. History groups by the current zone too (ADR 0004); accepted, noted in the ADR.

## 5. PR split

All on branches named after the ticket (`gln-2-widget-extension`, ...), titles per `pr-title.yml`. Line counts are production lines; tests, docs, xcstrings and `project.pbxproj` are listed separately.

### PR 1 — `docs(GLN-2): Decide the widget extension and the App Group boundary` (0 production lines)
ADR 0010 as in §1.3, with the status lines of ADR 0003 and 0004 marked "amended by 0010". Optionally bring `docs/spikes/17-widget-live-activity.md` to main (docs only) so the spike's findings are on main. Approved before PR 2 starts. Run the half-day spike item R1 in parallel (throwaway branch), so the ADR can name package or folder with evidence.

### PR 2 — `feat(GLN-2): Add the widget, showing today's practice` (~325 lines + ~130 pbxproj)
- pbxproj target (from the spike, minus `Shared`), `Config/Widgets.xcconfig`, `Config/Widgets.entitlements`, `Config/Widgets-Info.plist`, version keys to `Shared.xcconfig`, Makefile and CI lint dirs, README diagram. (~45 + pbxproj)
- `Packages/PianismGlance`: `Package.swift`, `AppGroup`, `PracticeWidget.kind` (~35; `PianismApp.appGroup` deleted)
- Core: `PracticeTotals` + `today(...)`, port `PracticeGlance { func show(_ totals: PracticeTotals) }` (~45)
- Persistence: `FilePracticeTotals` (~55)
- Features: `HistoryModel` writes on refresh; `Previews.swift` passes a preview glance (~12)
- App: `SystemPracticeGlance` (totals half, WidgetKit) and wiring (~45)
- Widgets: `PianismWidgets.swift`, `PracticeWidget.swift` with provider, view (total only; Start comes in PR 3), previews (~90)
Tests: core `PracticeTotalsTests` (Linux); persistence `FilePracticeTotalsTests` + `TotalsFileFormatTests`; features `HistoryModelTests` ("GLN-2: each refresh shows the widget today's finished practice, waiting sessions included, and nothing while history can't load"); end-to-end: every existing test now installs the app with the embedded extension (the real proof the target is wired; no new test). `make unused` must pass with the new target (R5). Device checklist rows W1–W3 (total after a save, after an edit, after midnight) with screenshots in the PR.
Why one PR despite ADR 0002's "own PR" for the project file: nothing else rides along but the widget's first feature, and the pbxproj lines are mechanical and reviewed as a block. If the owner prefers, split 2a (core + persistence + HistoryModel + app adapter, ~190) and 2b (target + widget, ~135 + pbxproj); 2a then ships a reload call with nothing to reload for a few days.

### PR 3 — `feat(GLN-2): Start a session from the widget` (~150 lines)
- Core: `PracticeSession.practiceOrigin` (~6); port gains `func show(_ session: PracticeSession?)` (~4)
- Features: `PracticeModel.init(glance:)`, `refresh()` calls `glance.show(session)`; `start/pause/resume/stop` become `public` (~12)
- PianismGlance: `GlanceCommands`, `StartPracticeIntent` (`LiveActivityIntent`, `isDiscoverable = false`, `openAppWhenRun` default false), the `AppIntentsPackage` conformance, `Resources/Localizable.xcstrings` (~45)
- App: register `GlanceCommands` (start only; the others in PR 4), the app's `AppIntentsPackage` listing the package, `SystemPracticeGlance.show(session)` reloading the widget on state/ID change, Debug hook `PIANISM_INTENT=start` that performs the intent at launch (~35)
- Widgets: the extension's `AppIntentsPackage`, the Start button, the running/paused look with the live total (~50)
Tests: core `PracticeSessionTests` for `practiceOrigin` (running, paused, resumed, ended); features `PracticeModelTests` ("GLN-2: each refresh shows the stored session outside the app, and nothing once it's archived or dropped"); end-to-end `testTheWidgetsIntentStartsASessionAndTheAppPicksItUp`: launch at `start` with `PIANISM_INTENT=start` → status "Practicing" → kill → relaunch at `start + 95 min` → "Still practicing?" shows (proves nudge pick-up) → relaunch at `start + 9 h` → the cap banner (same as `testSessionLeftRunningStopsAtTheCap`'s second half). This drives the exact in-process intent path, `@AppDependency` included, without SpringBoard. Device checklist rows W4–W8: Start with the app closed; after a force quit; with the app open on Practice (screen updates at once); with the phone locked (nothing happens); the widget reads "Practicing" after a reload. Compare with Apple's "Emoji Rangers" sample (interactive widgets, `Button(intent:)`) and the App Intents dependency sample; name both in the PR.

### PR 4 — `feat(GLN-1): Show the session as a Live Activity with Pause and Stop` (~280 lines)
- Core: port method becomes `show(_ session:, cappedAt: TimeInterval?)` (~2)
- Features: `PracticeModel` passes the cap for timer sessions; `perform(_:)` caps before the command (~8)
- PianismGlance: `PracticeAttributes` + `ContentState(session:cappedAt:)`, `Pause/Resume/StopPracticeIntent` (~60)
- App: ActivityKit half of `SystemPracticeGlance` (reconcile, request when enabled, update, end `.immediate`, serial task + `settle()`), the three commands, `PIANISM_INTENT=pause|resume|stop`, `INFOPLIST_KEY_NSSupportsLiveActivities` (~100)
- Widgets: `PracticeLiveActivity.swift` Lock Screen + island regions + previews in light, dark, AX5 (~110)
Tests: features `PracticeModelTests` ("SES-4, GLN-1: a Pause or Stop after the cap ends the session at the cap instead", "GLN-1: a MIDI session is shown with no cap", "GLN-1: the shown session is nil after Stop, after the cap and after a too-short session"); end-to-end `testTheLiveActivitysButtonsPauseAndStop`: running session, relaunch with `PIANISM_INTENT=pause` → "Paused", `resume` → "Practicing", `stop` → "Ready to practice" with "Last session". The activity itself cannot be asserted from XCUITest. Device checklist rows L1–L9: appears on Start from the app and from the widget (Lock Screen; island compact, minimal, expanded; centred clock); Pause/Resume/Stop from the Lock Screen and the expanded island, Practice agreeing; buttons after a force quit; Live Activities off in Settings (session still starts, no error, the widget updates); app killed and the cap passes (clock frozen at 4:00:00; next open ends the activity and archives 4 h); ended in the app → activity gone; AX5 text and VoiceOver on the buttons; iPad Lock Screen; a MIDI session's silence pause showing when the app returns. If the owner wants smaller PRs: 4a activity shows/updates/ends (~190), 4b the three buttons (~90).

## 6. Risks and unknowns, each with how to retire it

- **R1 (highest) App Intents in a Swift package.** `Button(intent:)` and the system need the intents' metadata in both bundles; with intents in a package that means `AppIntentsPackage` conformances in the package, the app and the extension, and Xcode's `appintentsmetadataprocessor` handling a *static* package product under Xcode 27. The spike avoided it with a folder. Retire in a half-day throwaway branch before PR 2's ADR is final: one intent in a package, the spike's widget tapping it on the simulator, `Metadata.appintents` present in both bundles. Fallback: a `Shared/` synchronized folder in both targets (spike-proven); the ADR names it.
- **R2 Background launch through the model.** The spike proved the intent runs in-app, but with `SessionRecorder` only. Unverified: that `PianismApp.init` (HistoryStore open, CloudKit, CoreMIDI client, notification delegate) completes before `perform()` so `@AppDependency` resolves, within the time the system allows, and when the app was suspended rather than killed. Retire on the same throwaway branch on the owner's iPhone with `os_log` lines in `init` and `perform`. Fallback: defer `historyStore.open()` and `CoreMIDINotes` until a scene connects.
- **R3 Live Activities turned off.** Does a `LiveActivityIntent` still run in-app when the user disabled activities? Untried by the spike. Retire: device check on the throwaway branch. Fallback (to avoid): a plain `AppIntent` in the extension writing the file, ADR 0003's original path, as a second code path.
- **R4 Updates after `perform()` returns.** `settle()` keeps the intent alive until ActivityKit took the change; verify Pause from the Lock Screen updates within a second, ten times, in L2.
- **R5 Tooling with a second target.** Periphery scanning the extension (protocol-driven types, `@main`, previews) and `appintentsmetadataprocessor` warnings under `scripts/fail-on-warnings.sh`. Retire: `make lint unused build` on PR 2's first push.
- **R6 Extension memory** (30 MB) with PianismPersistence linked (SwiftData/CloudKit symbols; the provider reads two small files). The spike ran it; measure with Xcode's gauge on the device during W1.
- **R7 Dynamic Island centring.** Fixed width + previews, then device (L1).
- **R8 Day boundaries and zones** for totals; the 8-hour activity limit for a session paused overnight (the system ends it; the next `show` requests a fresh one for a still-paused session). Accepted; Linux tests pin the calendar rule; the ADR records the limit.
- **R9 CI simulators and ActivityKit.** `Activity.request` may throw on a simulator without activity support; by design the adapter logs and continues, so no end-to-end test depends on it. Check PR 4's CI run.
- **R10 No mutation coverage for `App/` and PianismGlance.** By design; the rules (origin, totals, cap-before-command) live in core and features where tests and `make mutate` reach them.

## 7. Questions for the owner (only where the answer changes the work)

1. Layout: approve `Packages/PianismGlance` (iOS-only, shared types only) plus the adapter in `App/`, with the `Shared/` folder as R1's fallback? Or prefer the folder from the start (fewer moving parts, no `AppIntentsPackage` plumbing, no compile-time boundary)?
2. The widget while a session runs: show "Practicing/Paused" with a live total and hide Start (recommended; needs the reload on session change in PR 3), or always show Start (simpler widget, misleading while running)?
3. Resume on the Live Activity: the spec names Pause and Stop; without Resume a paused session must be resumed in the app. Recommended: Pause ⇄ Resume + Stop (one more intent and button).
4. PR size: one PR 2 (~325 lines + the project file) or the 2a/2b split?
5. A session capped while the app was away gets no SES-4 banner (only the process that capped it knows, and `cappedID` is in memory). Accept, or treat an archived session whose practice equals the cap as capped (about 5 lines in `PracticeModel.refresh()`, as the issue 47 comment suggests)?

Decisions taken without asking (say if you disagree): `.immediate` dismissal; compact island = symbol + clock only; intents hidden from Shortcuts (`isDiscoverable = false`); today-only totals file; the Debug `PIANISM_INTENT` seam in `PianismApp` alongside the other `PIANISM_*` variables.

## 8. Not verified (honest list)

- Everything in R1–R3 (package metadata, background-launch ordering, activities-off behaviour). SDK interfaces only were checked: `LiveActivityIntent` and ActivityKit are `@available(macOS, unavailable)`; `AppDependencyManager.add` requires `Sendable`; the wrapper is `@AppDependency`; `Text(timerInterval:pauseTime:countsDown:showsHours:)` exists; `Activity.end(_:dismissalPolicy:)` is async.
- The spec's own GLN wording beyond the acceptance criteria given to the agent.
- Whether `WidgetCenter.shared.reloadTimelines` from a background-launched app counts against the refresh budget (a few per day either way).
- Nothing was built or run; estimates are from reading the spike's files and main.

### Critical files for implementation
- App/PianismApp.swift (composition root: glance adapter, GlanceCommands registration, AppIntentsPackage, PIANISM_INTENT hook, AppGroup constant removal)
- Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeModel.swift (refresh → glance.show; public commands; cap before a command)
- Packages/PianismCore/Sources/PianismCore/PracticeSession.swift (practiceOrigin; whenPracticeReaches for the timer's end)
- Packages/PianismFeatures/Sources/PianismFeatures/History/HistoryModel.swift (writes today's total on refresh)
- ~/Developer/Pianism-spike: Pianism.xcodeproj/project.pbxproj and Widgets/PianismWidgets.swift (the target diff and view shape to reuse); docs/spikes/17-widget-live-activity.md
