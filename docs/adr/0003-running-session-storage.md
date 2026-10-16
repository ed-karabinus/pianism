# 3. The running session lives in the App Group, not the synced store

- Status: accepted; amended by [ADR 0007](0007-outbox-when-history-cant-save.md)
- Date: 2026-10-13
- Issue: #16

## Context and problem statement

A practice session that is still running can be changed from several places, some of them
separate processes:

| Where | Process | Changes |
| --- | --- | --- |
| Practice screen | App | start, pause, resume, stop |
| Live Activity buttons (GLN-1) | App, launched in the background | pause, stop |
| Small widget's Start button (GLN-2) | Widget extension | start |
| MIDI detector (M2) | App, foreground only | start, pause, resume, stop |
| Nudge and cap (SES-3, SES-4) | App | stop, end-time correction |

Finished sessions live in SwiftData, mirrored to the user's private iCloud database (SYN-1).
SES-6 and NFR-4 require a running session to survive the app being killed. Where should the
running session itself be stored?

The 13 Oct plan review flagged the obvious answer, storing it in the synced store and saving
every 30 s, as a source of sync churn, cross-process write races, and "running" sessions
appearing on the user's other devices.

## Considered options

1. **Synced SwiftData store**, saved on every change.
2. **App Group `UserDefaults`**, holding the encoded `PracticeSession`.
3. **One JSON file in the App Group container**, changed only through a coordinated
   read-modify-write, and moved into SwiftData when the session stops.

## Decision

Option 3.

- The running session is a single `PracticeSession` value (see `PianismCore`), encoded as JSON at
  `<App Group>/running-session.json`. No file means no running session.
- The core defines a port, `RunningSessionStore`, with two operations: `current()` and
  `update(_ change: (inout PracticeSession?) throws -> Void)`. Every change is a read-modify-write
  of the whole value.
- The adapter implements `update` with `NSFileCoordinator`, so the app and the widget extension
  never interleave a read and a write, and writes the file atomically, so a crash never leaves
  half a file.
- **Only the app moves sessions into SwiftData.** When a session stops in the app, it is inserted
  into the store and the file is deleted in the same step. When the widget or a Live Activity
  stops one, it stays in the file, marked ended, and the app moves it on its next launch or
  return to the foreground. Each store has exactly one writer.
- Elapsed time is always derived from the stored timestamps, so there is no periodic save. Each
  change writes once.

Option 1 is rejected because CloudKit mirroring would sync every pause and resume, other devices
would show sessions that are still running, and SwiftData contexts in two processes would race
on the same store. Option 2 is simpler, but `UserDefaults` offers no atomic read-modify-write
across processes: a widget Stop and an app Pause at the same moment could silently lose one.

## Consequences

- Good: unfinished sessions never sync, and the synced store only ever receives finished,
  immutable sessions, which also simplifies conflict handling for SYN-1.
- Good: crash-safe by construction (SES-6). Every change is persisted before it's acknowledged.
- Good: the port is trivial to fake in core tests (`InMemoryRunningSessionStore`); the coordinated
  adapter gets its own integration tests, including two writers racing.
- Bad: a session stopped from the widget appears in History only after the app next runs.
  The widget shows the running or just-stopped session from the file, so the user doesn't see
  the gap.
- Bad: `NSFileCoordinator` isn't available on Linux, so the adapter lives in a separate
  Persistence package, tested on macOS only (consistent with ADR 0001).
- To verify early: the M1 spike (#17) confirms that a widget intent can write this file and
  start a Live Activity without opening the app.
