# 9. A MIDI session stores nothing new; its played time comes from its pauses

- Status: accepted
- Date: 2026-10-23
- Amends: [ADR 0006](0006-schema-v1-before-deploy.md)
- Issue: #119, before MIDI-1 (#43)

## Context and problem statement

MIDI-1 records sessions from a connected piano: a session starts at the threshold's first note,
pauses after a silence, and ends 5 s after its last note. The spec's data model named figures that
schema v1 doesn't hold: `pausedSeconds`, `playedSeconds` and `noteCount`, and its Pro tier sold
"played vs. bench time, note counts".

Schema v1 is deployed to CloudKit Production. Fields can be added, never renamed or removed, and
each addition costs an ADR 0008 deploy before any Release build writes it, plus a fixture store.

What has to be stored depends on where a Playing span ends. The MIDI spec review (2026-10-17) found
that if it ends when the silence timer fires, played time can exceed the session's length (138.7 s
played in an 83.75 s session), and the backdated end throws `timeWentBackwards`. The owner decided
the open questions on 2026-10-23 (#119).

## Considered options

1. **Store `playedSeconds` and `noteCount`.** Follows the spec's table, but played time duplicates
   what the pauses already say, and the two can disagree after an edit.
2. **Store `noteCount` only, and derive played time from the pauses.**
3. **Store nothing new.** MIDI-1 needs no deploy (`midi` is already a valid `source`), but if note
   counts are wanted later, sessions recorded before that deploy never get one, and a count can't
   be rebuilt.
4. **One JSON field for MIDI figures,** like `pauses`, that can gain keys without a deploy. Only
   worth it with more figures planned for v1.x; it's opaque in CloudKit Console.

## Decision

Option 3. The owner first chose option 2, then dropped note counts the same day: "I don't see value
in them for a musician" (owner, 2026-10-23). The spec no longer has them.

- **A Playing span ends at its last note.** After the pause timeout (60 s by default), the session
  pauses at its last note, not when the timer fires. A note while paused resumes it at that note.
  However a session ends, a pause at its last note is recorded first, so the 5 s to its end are a
  closing pause; a Stop tapped sooner than that ends it at the tap, with no tail. So a MIDI session's
  practice time, `elapsed(at:)`, is its played time (MIDI-R2), and its pauses are its bench time.
  Silences shorter than the timeout stay inside played time, as the spec says.
- **The detector's effects are dated,** and `SessionRecorder` gains `start(at:)`, `pause(at:)` and
  `resume(at:)` to take them; `stop(at:)` already exists. MIDI-1's core plan specifies them.
- **Schema v1 stays as it is.** `playedSeconds` isn't stored, and no note count is recorded, so
  MIDI-1 needs no deploy.
- **`PracticeSession` gains `Source.midi`,** with a sample in `SessionFileFormatTests` (ADR 0003).
- **Stored sources** are `timer`, `manual` and `midi`. The spec's old "manual" session is the code's
  `timer`, started and stopped by taps; the code's `manual` is a session added after the fact
  (SES-5).
- **A session started by tapping Start stays `timer`** when notes arrive (MIDI-R4): the notes only
  count as activity for "Still practicing?". It doesn't pause or end by itself, has no played/bench
  split and doesn't use one of PRO-2's five free sessions.
- **Stop on a MIDI session** ends it at the earlier of the tap and 5 s after the last note. A run
  with under a minute of played time is never saved.
- **`version` stays 1.** Builds since #122 keep a source they don't know, so an older app's edit
  can't lose `midi`. Only development builds on the owner's devices predate that, and their data
  may be wiped (owner, 2026-10-23).
- **Left to MIDI-1's plan:** which clock the note times come from, and saving the last note's time
  to the running-session file when the app goes to the background, so a kill while playing doesn't
  lose it.

## Consequences

- Good: MIDI-1 needs no CloudKit deploy. HIS-4's played and bench time and EXP-1's export come from
  fields v1 has.
- Bad: if note counts come back, MIDI sessions recorded before their deploy never have one.
- Bad: while a session is going, the on-screen timer keeps counting through a silence, then drops
  back by up to the pause timeout when the pause starts. MIDI-1's plan designs that moment,
  including the Live Activity's timer.

Amended 2026-10-24 by MIDI-1: a note is dated by the app's clock when it reaches the app, not by
CoreMIDI's timestamp. Bluetooth delivers notes about 10–30 ms late, which is nothing against the
detector's 10 s, 60 s and 600 s, and one clock keeps notes in step with every other change, including
the fixed clock of the end-to-end tests. If a device ever needs exact note times, the change stays
inside `CoreMIDINotes`.
