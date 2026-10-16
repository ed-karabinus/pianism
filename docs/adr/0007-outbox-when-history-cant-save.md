# 7. Finished sessions wait in an outbox when history can't save them

- Status: accepted
- Date: 2026-10-16
- Amends: [ADR 0003](0003-running-session-storage.md)

## Context and problem statement

A finished session moves from the running-session file (ADR 0003) into history. Only one session
fits in that file, and `start` refuses while an ended one waits there, so it never overwrites
practice. So if history can't save, practice stops: every Start is refused until it can.

History may fail to open after a bad schema migration, a full disk or a corrupted file. A bad
migration hits every user at once, until a fix passes App Review, which can take days. Refusing
Start then keeps one finished session safe and loses all the practice nobody can time.

## Considered options

1. **Refuse Start** until history saves the waiting session (the behaviour before this ADR).
2. **Start anyway** and discard the waiting session.
3. **An outbox:** finished sessions wait in their own files until history can save them.

## Decision

Option 3, chosen by the owner on 2026-10-16.

- **Archiving,** when a session ends, tries history first. If history fails, the session goes to
  the outbox, and the running-session file is cleared either way, so Start always works. Only when
  the outbox fails too does the session stay in the running-session file, and Start is refused, as
  before.
- **Every archive retries** the waiting sessions: each is saved to history, then removed from the
  outbox. History replaces by ID, so a crash between those two steps only repeats a save.
- **The outbox lives in the app's own Application Support folder,** one JSON file per session, not
  in the App Group. Only the app archives sessions, and separate files mean adding or removing one
  never rewrites another.
- **Practice says what's waiting:** "2 sessions waiting to be saved", in place of an alert on every
  tap. History still says it couldn't load.
- **History retries opening** on the next call after a failure, so a passing cause, such as a full
  disk, heals without a relaunch.

Option 1 is rejected because it loses more practice than it protects. Option 2 is rejected because
it loses data outright.

## Consequences

- Good: practice never stops because history can't save, and no finished session is lost unless the
  disk can't take even a small file.
- Bad: while history is down, waiting sessions don't show in History. History says it couldn't
  load, and Practice says how many are waiting.
- Bad: a third place a session can be, besides the running-session file and history. Each move
  between them is safe to repeat, which the tests check.
- Bad: a session history refuses every time (one that wouldn't read back the same, ADR 0006) stays
  in the outbox, logged, and the sessions listed after it wait behind it. Moving past it would
  repeat a failed open for each waiting session during an outage. A waiting file that can't be read,
  as after a format change, is skipped and kept.
