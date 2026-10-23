# 9. A MIDI session stores its note count, added in one deploy; its played time comes from its pauses

- Status: accepted
- Date: 2026-10-23
- Amends: [ADR 0004](0004-synced-data-model.md), [ADR 0006](0006-schema-v1-before-deploy.md)
- Issue: #119, before MIDI-1 (#43)

## Context and problem statement

MIDI-1 records sessions from a connected piano: a session starts at the threshold's first note,
pauses after a silence, and ends 5 s after its last note. The spec's data model names figures
that schema v1 doesn't hold: `pausedSeconds`, `playedSeconds` and `noteCount`, and its Pro tier sells "played vs.
bench time, note counts".

Schema v1 is deployed to CloudKit Production. Fields can be added, never renamed or removed, and
each addition costs an ADR 0008 deploy before any Release build writes it, plus a fixture store. A
`version` bump would also make every record the new build writes read-only on older installs until
they update (ADR 0006). Several small additions over M2 to M4 multiply those costs, so MIDI's fields
go in one deploy.

What has to be stored depends on where a Playing span ends. The MIDI spec review (2026-10-17) found
that if it ends when the silence timer fires, played time can exceed the session's length (138.7 s
played in an 83.75 s session), and the backdated end throws `timeWentBackwards`. The owner decided
the open questions on 2026-10-23 (#119).

## Considered options

1. **Store `playedSeconds` and `noteCount`.** Follows the spec's table, but played time duplicates
   what the pauses already say, and the two can disagree after an edit.
2. **Store `noteCount` only, and derive played time from the pauses.**
3. **Store nothing new yet.** MIDI-1 needs no deploy (`midi` is already a valid `source`), but
   sessions recorded before a later deploy never get a count, and the count can't be rebuilt.
4. **One JSON field for MIDI figures,** like `pauses`, that can gain keys without a deploy. Only
   worth it with more figures planned for v1.x; it's opaque in CloudKit Console.

## Decision

Option 2.

- **A Playing span ends at its last note.** After the pause timeout (60 s by default), the session
  pauses at its last note, not when the timer fires. A note while paused resumes it at that note.
  However a session ends, a pause at its last note is recorded first, so the 5 s to its end are a
  closing pause; a Stop tapped sooner than that ends it at the tap, with no tail. So a MIDI session's
  practice time, `elapsed(at:)`, is its played time (MIDI-R2), and its pauses are its bench time.
  Silences shorter than the timeout stay inside played time, as the spec says.
- **The detector's effects are dated,** and `SessionRecorder` gains `start(at:)`, `pause(at:)` and
  `resume(at:)` to take them; `stop(at:)` already exists. MIDI-1's core plan specifies them.
- **`SessionRecord` gains one field,** `noteCount: Int?`. `nil` means the session has no MIDI data, which
  includes a session started by tapping Start (below).
  It's a number, so it isn't encrypted. `playedSeconds` isn't stored.
- **The note count** is the number of Note Ons with velocity above 0 (MIDI-R1), from the threshold's
  first note to the last, counting each key of a chord (owner, 2026-10-17). Notes before the
  threshold are left out.
- **`PracticeSession` gains `Source.midi` and an optional note count,** stored as optionals like its
  tags, so running-session and outbox files written before still decode (ADR 0003). The format
  change adds a sample to `SessionFileFormatTests`.
- **Stored sources** are `timer`, `manual` and `midi`. The spec's "manual" session is the code's
  `timer`, started and stopped by taps; the code's `manual` is a session added after the fact
  (SES-5).
- **A session started by tapping Start stays `timer`** when notes arrive (MIDI-R4): the notes only
  count as activity for "Still practicing?". It doesn't pause or end by itself, has no played/bench
  split and doesn't use one of PRO-2's five free sessions.
- **Stop on a MIDI session** ends it at the earlier of the tap and 5 s after the last note. A run
  with under a minute of played time is never saved.
- **Edits keep the note count and the source.** An edit that shortens a MIDI session keeps the
  count it was recorded with.
- **`version` stays 1.** ADR 0006 bumps it when an older app would lose a field or value by saving.
  MIDI-1 ships in 1.0, and no TestFlight or App Store build goes out before it merges, so no
  public build lacks `noteCount` or `midi`. Only development builds on the owner's devices predate
  them, and their data may be wiped (owner, 2026-10-23). Builds since #122 also keep a source they
  don't know.
- **Schema v2** adds the field through a lightweight migration stage. It gets its own fixture store,
  with a MIDI session and a count, beside v1's, and v2 copies of the fields file and the `.ckdb`.
- **The deploy** follows ADR 0008's six steps, with step 2 reading "Development equals Production"
  rather than empty. Debug builds may write the field to Development
  before the deploy; no Release build that writes it runs on the owner's iPhone until Production
  has it.
- **Left to MIDI-1's plan:** which clock the note times come from, and saving the last note's time
  and the running count to the running-session file when the app goes to the background, so a kill
  while playing loses neither.

## Consequences

- Good: one deploy covers MIDI-1 and everything planned through M4. HIS-4's played and bench time,
  EXP-1's export and PRO-2's count all come from fields v2 has.
- Bad: while a session is going, the on-screen timer keeps counting through a silence, then drops
  back by up to the pause timeout when the pause starts. MIDI-1's plan designs that moment,
  including the Live Activity's timer.
- Bad: a deploy during M2, for a figure nothing shows before M4.
