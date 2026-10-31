# 10. A widget extension shows practice outside the app, and only the app writes what it shows

- Status: accepted
- Date: 2026-10-31
- Amends: [ADR 0003](0003-running-session-storage.md), [ADR 0004](0004-synced-data-model.md)
- Issue: #47 (GLN-1), #48 (GLN-2); spike #17

## Context and problem statement

GLN-2 puts a small Home Screen widget on the phone: today's practice total and a Start button.
GLN-1 shows the running session on the Lock Screen and in the Dynamic Island as a Live Activity,
with Pause, Resume and Stop. Both run outside the app, in a process the system starts and stops
as it likes, with no network, little memory and a 4 KB limit on what a Live Activity can show.

Spike #17 (branch `spike-17-widget-live-activity`, 2026-10-16) proved the shape on a device: a
widget button named a `LiveActivityIntent`, the system launched the app's process in the
background to run it, the intent wrote the running session to the App Group file (ADR 0003) and
started the Live Activity, and the app showed the session when opened, including after a force
quit. It also found that Home Screen automation on the simulator stalls for minutes per tap, so
widget taps can't be end-to-end tests.

ADR 0003 and ADR 0004 were written before the spike and assumed the widget extension itself
writes the running session and reads a 7-day summary. The questions now: which process changes
a session, what the extension may read, where the shared types live, and how the parts that
build only for iOS are tested.

## Considered options

1. **The extension writes.** The widget's Start writes the App Group file itself through the
   core's `SessionRecorder`, as ADR 0003's table says. Two writer processes, each needing the
   core, the persistence adapter and a clock.
2. **The app is the only writer.** Every button, on the widget and on the Live Activity, is a
   `LiveActivityIntent`, which the system runs in the app's process. The extension only renders
   what it reads. One writer, one place for the rules (the nudge, the cap, MIDI pauses).
3. **Update the Live Activity by push** from a server instead of from the app's process. Still
   needs the extension and the intents, and adds a server to a local-first app.

For where the shared types live (the intents, the Live Activity's attributes, the totals file's
format):

- a. **A local package, `PianismGlance`**, iOS-only, holding shared types only, like the other
  packages (ADR 0002). The compiler enforces that the extension sees nothing else.
- b. **A `Shared/` folder** compiled into both targets, as the spike did. Fewer moving parts, no
  compile-time boundary.

## Decision

Option 2, with the shared types in a package (a). The folder (b) was the fallback in case App
Intents couldn't be built from a package; a check on 2026-10-31 (a local branch,
`spike-r1-intents-package`, with its build log in the PR) built one `LiveActivityIntent` from a
static local package into both bundles' App Intents metadata. Two things that check settled: an
`AppIntentsPackage` is declared as its own small struct in the package, the app and the
extension, and the package stays out of `make test-adapters`, since ActivityKit and
`LiveActivityIntent` don't exist on macOS.

- **One new target, `PianismWidgets`**, a WidgetKit extension embedded in the app, hosting both
  the small widget and the Live Activity. A Live Activity's configuration must live in a widget
  extension, and Apple's samples use one extension for both. No other extension.
- **The extension only reads.** It links `PianismGlance`, `PianismCore` and `PianismPersistence`
  to read two App Group files: the running session (ADR 0003) and a totals file the app writes,
  `practice-totals.json`, holding today's finished practice. It adds the running session to that
  total itself. It never links `PianismFeatures` (whose views use app-only API), never opens the
  SwiftData store (ADR 0004) and never writes.
- **Every button is a `LiveActivityIntent`**, so the system runs it in the app's process, launched
  in the background if need be. The intents hold no rules: each calls a command the app registers
  at launch (`GlanceCommands`, through App Intents' dependency manager), and the commands call
  `PracticeModel`'s start, pause, resume and stop, so a Stop from the Lock Screen takes the same
  path as a Stop on the Practice screen, cap and nudge included.
- **Only the app starts, updates and ends a Live Activity.** `PracticeModel` shows the stored
  session through a port, `PracticeGlance`, after every change; the adapter,
  `SystemPracticeGlance`, reconciles the system's activities with the stored session, so an
  activity that outlived a killed app is updated or ended on the next launch. The clock runs on
  the Lock Screen by itself, with its range ending at the cap; only a pause, a resume, a stop or
  the cap sends an update. Starting the Live Activity can fail (Live Activities off in Settings)
  and that never fails the session.
- **The adapter lives in `App/`**, not in a package: ActivityKit and `LiveActivityIntent` are
  unavailable on macOS, so it can't join the macOS-tested adapters (ADR 0001) or `make mutate`.
  What covers it instead: the build, previews for every widget and activity state, end-to-end
  tests that drive the same in-process intent path through a Debug-only launch variable that
  performs an intent at launch, and the device checklist for the widget and the Live Activity
  themselves.
- **The widget while a session runs** shows "Practicing" or "Paused" with the live total, and
  hides Start (decided with the owner, 2026-10-31). The app reloads the widget on every session
  change.
- **Resume joins Pause and Stop** on the Live Activity (decided with the owner, 2026-10-31; the
  spec's GLN-1 line is amended with the PR that adds it).

## Consequences

- Good: one process holds every rule about a session. A widget Start, a Lock Screen Stop and a
  Practice-screen Stop are the same code, so the cap, the nudge and MIDI's silence pauses apply
  everywhere without a second implementation.
- Good: the extension is small and can't corrupt anything. It reads two files and draws.
- Good: every rule (today's total, where a session's practice time starts, the cap before a
  command) stays in the Linux- and macOS-tested packages. `PianismGlance` and the adapter in
  `App/` hold types and glue with no rules, and the build, the previews and the end-to-end tests
  cover them.
- Bad: nothing here is a CI end-to-end test. Tapping a widget and seeing a Live Activity are
  device checks, listed in each PR, as the spike found.
- Bad: the totals file is a second copy and can be stale. A session synced from another device
  shows in the widget only after the app next opens, and after a time-zone change the widget may
  show 0 until the app next writes.
- Bad: a cap reached while no process is running is only applied when the app next runs. The
  Lock Screen clock stops by itself at 4:00:00, because its range ends at the cap, but the
  session is ended and archived at 4 h only then, and the app shows the cap banner for a session
  archived at exactly the cap (decided with the owner, 2026-10-31).
- Accepted: no new background mode; `remote-notification` stays the only one (NFR-9, as amended
  2026-10-20). Widget buttons need an unlocked phone (Apple). A Live Activity lasts at most
  8 hours, which holds the 4-hour cap (SES-4); a session paused overnight outlives its activity,
  and the app asks for a new one when it next runs.
- Still a device check: that a tap on the widget built this way runs the intent in the app, as
  it did on the spike's folder build, and that the app's launch finishes before the intent runs,
  so the registered commands are there. The metadata in both bundles is what the system routes
  by, so the widget PR's device checklist covers it.
