# Slot 9 (HIS-1, HIS-2, GLN-2, SET-1): a session across midnight shows on each day it touches — implementation plan

Written 2026-11-05 by a Fable 5.1 plan agent (read-only) against main at 13971c0. Nothing was built or run.

Sources:
- Ed's decisions of 2026-11-04, as given in the brief (§1).
- CLAUDE.md, `docs/decisions.md`, ADR 0004 and ADR 0006 ("Time zone"), `docs/device-checklist.md` (W3, R1, R2), `docs/plans/plan-gln.md` §4.
- The spec's HIS-1, HIS-2, HIS-3, GLN-2 and SES-5 rows, read on 2026-11-05 (quoted in §2).
- The code and tests named under "Critical files", read in full.

Anything not verified is listed in §9.

## Short summary

- **What changes:** one stored session, one History row for each day it has practice in. Each row shows that day's minutes; the editor shows the whole session. Day, week and widget totals add the rows, so they still match what's on screen (the promise #183 made). The daily reminder's "practiced today" becomes "minutes played today".
- **How, cheaply:** `PracticeDay.group` walks the days a session touches instead of keying on its start, and a new `part(of:)` gives a row its span and whole seconds. Everything that totals reads parts. About 55 production lines, most in the core. Nothing stored changes.
- **Two PRs:** rows and totals (~55 lines), then the editor and delete dialog saying a change reaches both rows (~20 lines). One PR of ~75 if you settle the wording (Q2) now, which I'd prefer.
- **Tests:** three core tests flip, not two: `PracticeWeekTests.otherWeeksDontCount` has a Sunday 23:30 session that now puts 30 minutes into the week under test. No features or end-to-end test flips in a US or UTC time zone. One new end-to-end test covers what W3 checked by hand; W3 keeps only the widget's own screen.
- **Spec:** no line has to change. I read HIS-1, HIS-2, HIS-3, GLN-2 and SES-5 and searched for "midnight", "day it started", "counts toward" and "today" (§2). The rule lives in ADR 0004 alone, which gets an amendment, and `docs/decisions.md` a row, both in PR 1.
- **Questions:** six, in §8. Q1 and Q5 block PR 1; Q2 blocks PR 2.

## 0. What you'll see change

Leading with the awkward parts.

1. **Two rows, one session.** A session from 11:30 PM to 12:30 AM shows under Yesterday as `11:30 PM – 12:00 AM  30:00` and under Today as `12:00 – 12:30 AM  30:00`. Tapping either opens the same editor: Start 11:30 PM yesterday, End 12:30 AM today, Practice time 1:00:00. (Q1 asks whether each row shows its own span, as here, or the whole session's.)
2. **Where the rows sit.** Within a day, newest first by start, as now. The carried-over row is the earliest practice of its new day, so it's the bottom row under Today and the top row under Yesterday.
3. **Headers and the week.** Yesterday's header counts 30 minutes, Today's 30. The week chart gives each day its own bar. A session across the Saturday/Sunday midnight splits between two weeks, and each week's total and by-tag times count only their side.
4. **Tiny tails look odd.** A session stopped at 12:00:12 AM gives Today a row `12:00 – 12:00 AM  0:12`: the time formatter shows the same minute twice when the span is under a minute. You decided tiny parts show as they are, so I've left this; the alternative is a special case in the title.
5. **A pause across midnight gives no row.** A session paused at 11:50 PM and resumed at 12:10 AM, stopped at 12:30, shows 20 minutes under Today and its earlier minutes under Yesterday. One paused at 11:50 and stopped at 12:05 while paused shows only under Yesterday, though its End is today. Decided.
6. **One second.** Each row rounds down on its own, so two rows can add to one second less than the editor: editor 59:59, rows 39:59 and 19:59, which is 59:58. Day and week totals equal their rows, so #183's promise holds; the second is visible only to someone adding two rows and comparing with the editor. The other way round, giving the lost second to one row, would show a row with more than was practiced that day, which the widget and the clock never do. I recommend rounding each part down.
7. **Editing or deleting either row changes both.** The editor gets a footer saying so (Q2), and the delete dialog says both rows go. Undo brings both back. These are PR 2.
8. **The widget.** Once Pianism has been opened after midnight, today's total includes this morning's minutes of a session that started last night; today it shows 0 for them. The running clock already counts from midnight (#184). The Live Activity and Practice's "Last session" show the session, not a day, so they don't change.
9. **The reminder.** A session started last night and stopped this morning now counts as practice today, so today's reminder is skipped; today it counts for yesterday and the reminder still comes. A session paused on an earlier day with no practice today still doesn't count (decided 2026-11-05). A tail of a few seconds does count (Q3).
10. **Old history moves.** Sessions already stored are shown split from the first launch after the update; nothing is rewritten. A late session you've seen under one day now has its after-midnight minutes under the next, and past weeks with a Saturday-night session lose those minutes to the following week.
11. **VoiceOver** reads a row as "12:00 to 12:30 AM, Untagged, 30 minutes": the row's span and tags, then its minutes. Day and week headers read as now.

## 1. What Ed decided (2026-11-04), not reopened here

- A session that crosses midnight is split across the days: one row on each day, both the same session.
- Editing or deleting either row changes both, and the app says so.
- Tiny parts are shown as they are. A part with no practice in it, like a pause across midnight, gets no row.
- Nothing stored changes.
- This reverses ADR 0004's "A session counts toward the day it started": late-practicing conservatory students, and unknown session lengths. "Today's practice" means the minutes played today.

## 2. The spec and the decision records

The spec's rows, verbatim (Feature spec table, read 2026-11-05):

| ID | Requirement | Acceptance criteria | Priority, milestone |
|---|---|---|---|
| HIS-1 | Session history | "List grouped by day, newest first, with duration and tags; each day header shows the day's total" | Must, M1 |
| HIS-2 | Weekly view | "A bar per day for the current week, the week's total, a breakdown by tag; swipe to earlier weeks" | Must, M3 |
| HIS-3 | Weekly consistency | "Shows "practiced N of 7 days this week" and "weeks meeting your goal this year" (goal default 3 days); nothing ever resets to zero" | Should, M3 |
| GLN-2 | Widgets | "Small widget only: a Start button and today's total; Start begins a session without opening the app" | Must, M3 |
| SES-5 | Add, edit, delete sessions | "Start, end, tags and notes are editable; sessions can be added after the fact; delete confirms and can be undone for 5 s" | Must, M1 |

Searches of the whole spec: "midnight" 0 hits; "day it started" 0 hits; "counts toward" 1 hit, in MIDI-R4 (about notes and "Still practicing?"); "today" 1 hit, GLN-2's "today's total". So the earlier claim holds: **no spec line has to change.** "The day's total" and "today's total" read more naturally with the split than without it. I'm proposing no spec edit and asking for no authorization.

The rule lives in three places, all ours to change:

- **ADR 0004**, Decision section: "Grouping by day, day totals and week totals are pure core functions over values (HIS-1, HIS-2). They are tested on Linux, including time zones and daylight-saving changes. **A session counts toward the day it started.**" The ADR README says a refinement is a dated "Amended" note in the record, not a new ADR, and this changes one rule, not the architecture. Proposed note, added after that paragraph in PR 1:

  > Amended 2026-11-05 by HIS-1 (#NNN): a session that crosses midnight shows on each day it has practice in, with that day's minutes, so "today's practice" is the minutes played today (decided with Ed, 2026-11-04: students who practice late, and sessions of unknown length). Each day's total adds its rows (#183). The stored session is unchanged; the split is worked out when History groups. Editing or deleting any of its rows changes the one session.

- **`docs/decisions.md`**, new row in PR 1:

  > | 2026-11-04 | Settled | A session across midnight shows under each day it has practice in, with that day's minutes; editing or deleting any row changes the one stored session. | Late-practicing students and sessions of unknown length: today's practice is what was played today. |

- **Code comments and test names** that say "the day it started": `PracticeDay.swift`, `PracticeTotals.swift`, `HistoryModel.swift`, and the two tests in §6.

## 3. Design

### 3.1 Core (Linux-tested)

**`PracticeSession.practiced(from:before:)`.** Today's `practiced(before:)` clips each practice span at `date`. It gains a `from` with a default of `.distantPast`, and the reduce clips both ends: `max(0, min(spanEnd, before) - max(spanStart, from))`. The widget's `todaysClock` keeps calling `practiced(before:)`. Why not `practiced(before: end) - practiced(before: start)`: subtracting two sums of real timestamps can land a hair under a whole second, and rounding down would then lose it. Clipping once has no such step. About 3 lines.

**`PracticeDay`** gains `end` (the day's last moment, from the calendar, as `PracticeWeek` already works out for empty days) and:

```swift
/// A session's practice within this day: when it ran here, and its whole seconds, which the row shows.
public struct Part: Sendable, Hashable { public let span: Range<Date>; public let practiced: TimeInterval }
public func part(of session: PracticeSession) -> Part
```

`part(of:)` is `session.practiced(from: start, before: end).rounded(.down)` and `max(startedAt, start)..<min(endedAt, end)`. `total` is the sum of `part(of:).practiced` over the day's sessions, so a header always equals its rows.

`group` walks the days a session touches, from `startOfDay(startedAt)` to `startOfDay(endedAt)`, one `calendar.date(byAdding: .day, value: 1)` at a time, and lists the session under each day where its part is at least one whole second. That settles two of your points:

- **Several midnights (point 2):** the loop has no notion of "two days". A manual session entered as Monday 10 PM to Wednesday 7 AM gets three rows; a timer session paused Friday night and stopped Monday gets no rows for the days with no practice. The cost is one iteration per day touched, which for a few thousand sessions is nothing.
- **Rows that round to nothing:** a part under one second would read `0:00` and add nothing to the total, so it gets no row. The threshold is "at least one whole second", the same unit the rows use.

`wholeSecondsPracticed` loses its last caller (see `timeByTag`) and is deleted.

**`PracticeWeek`.** Empty days get `end` (2 lines). `timeByTag` adds `day.part(of: session).practiced` for each session in each of the week's days, in place of the session's whole seconds (point 4). That counts a crossing session once per day it's in, each day with its own minutes, and since a week is seven `PracticeDay`s, a session across the week's first midnight contributes only its inside part. No other change.

**`PracticeTotals(from:at:in:)`** doesn't change: it already takes today's `PracticeDay.total`, which is now today's minutes of finished sessions, whenever they started. Its doc comment ("sessions that started that day") is reworded.

**Rejected:**
- `PracticeDay.sessions` becoming `[Part]`: cleaner on paper, but every `days.map(\.sessions)` in the tests, every `flatMap(\.sessions)`, `ForEach(day.sessions)` and the row's identity change with it. Keeping `sessions: [PracticeSession]` and adding `part(of:)` touches a tenth of the code.
- Storing the parts in `PracticeDay` at grouping time: a dictionary to keep in step with `sessions`, for a value that's three subtractions to recompute.
- Clamping to "the start day and the next": wrong for manual entries, which the editor lets start on any earlier day.
- Splitting the stored session into two: you ruled it out, and it would be a sync write with a migration.

### 3.2 Features

**`HistoryModel`** keeps the flat list it grouped, `private(set) var sessions: [PracticeSession]`, beside `days`. The three `flatMap(\.sessions)` sites (point 5):

| Site | Today | After |
|---|---|---|
| `edit(id:)`, line 174 | `days.lazy.flatMap(\.sessions).first(where:)` | `sessions.first(where:)`. A duplicate would have been harmless (`first`), but the flat list says what's meant. |
| `otherSessions(at:)`, lines 202 and 207 | `days.flatMap(\.sessions)`, feeding the overlap warning and `add()`'s "keep clear" rule | `sessions`. With duplicates, `overlap` would have tested the same session twice and `add()` moved its end back twice; both harmless in effect, both wasteful. |
| `dayWithPractice(at:)`, line 114 | `!$0.sessions.isEmpty` | Unchanged: it asks about one day. |
| `HistoryView`, line 123 | `ForEach(day.sessions)` | Unchanged: within one day a session appears once, and a `ForEach`'s identifiers are scoped to it. |
| `Previews.swift`, line 110 | `days.first?.sessions.first` | Unchanged. |
| Tests comparing `model.days.flatMap(\.sessions)` | Fixtures at 2027-01-01 00:00 UTC, none crossing with practice on both sides (§6) | Unchanged. |

**`HistoryView`.** The row takes `let part = day.part(of: session)`: title from `part.span`, formatted as `PracticeSession.times` formats a session (one small helper on `Range<Date>` that both use), duration `part.practiced`. The "not saved yet" title uses the same span. `PracticeSession.times` stays for the overlap warning, which names a session. About 8 lines.

**Row identity (point 6).** Two rows share a session ID, in two `ForEach`es, so SwiftUI never sees a duplicate. The editor sheet is keyed by `SessionEdit.id`, which is the session's: one editor whichever row is tapped. `delete(_:)` hides by `pendingDeletion?.id`, so both rows go and Undo brings both back, with no new code.

**Overlap warnings (point 6).** `sharedPractice(with:)` compares two sessions' practice spans, so a session across midnight overlapping another is found as today. The footer's "so the day's total counts it twice" stays true of each day the shared minutes fall in. No change.

**The daily reminder (point 3).** `PracticeModel.hasPracticedToday` becomes: a running session counts, whenever it started (unchanged); otherwise any session in the store, history or outbox with at least one whole second of practice between today's start and tomorrow's: `practiced(from: today, before: tomorrow) >= 1`. For a paused session the open pause runs to `before`, so only its practice counts. Exactly what changes:

| Session | Today | After |
|---|---|---|
| Started yesterday 11:30 PM, stopped today 12:30 AM | Not today's practice: the reminder comes | Today's practice: the reminder is skipped |
| Started yesterday 11:30 PM, paused today 12:10 AM, still paused | Not today's | Today's: 10 minutes were played today |
| Paused yesterday 11:50 PM, resumed today 12:10, stopped 12:30 | Not today's | Today's |
| Started yesterday, paused yesterday, still paused | Not today's | Not today's (the 2026-11-05 decision holds) |
| Running since yesterday | Today's | Today's |
| Ended but stuck in the store after a storage failure | Counts for its start day | Counts for each day it has practice in |
| Stopped at 12:00:04 AM, four seconds in today | Not today's | Today's (Q3) |

It's the same "at least one whole second" rule History's rows use, so the reminder and History agree by construction; a core test pins `practiced(from:before:)` and three features tests pin the first, third and fourth rows above.

**HIS-3 (point 3, not built).** Recommendation: a day is practiced if History lists a row for it, the same rule. "Practiced N of 7 days" then matches the chart's bars, and a late-night student who stops at 12:03 has practiced on both days. If you want a minimum, say ten minutes, that's HIS-3's own threshold and should wait for its plan (Q4).

**The widget and the Live Activity (point 6).** The widget already gets its total from `PracticeTotals(from: days, …)`, so it follows History with no change. `SystemPracticeGlance`'s fallback totals for a widget Start (`startOfDay(for: session.startedAt)`) are right as they are: at Start, the session's start is now. The Live Activity shows the session's own clock, which doesn't change. The widget's running clock counts from midnight since #184, so after this PR its figure and History's Today header are two views of the same number.

**Time zones and DST (point 7).** Midnight is `Calendar.autoupdatingCurrent`'s, the calendar History, Practice and the widget already group with. A session recorded in Tokyo and viewed in Los Angeles splits at Los Angeles's midnight, as it's grouped under Los Angeles's day today; the stored `timeZone` (ADR 0006) stays unused, as ADR 0006 says it is. Days of 23 and 25 hours come from `startOfDay` and `date(byAdding: .day)`, as `PracticeWeek` does it; where clocks skip midnight (Santiago), the day starts at 1:00 and a session across it splits there. Tests in §5 cover both. Nothing else to do.

### 3.3 Saying so (PR 2)

- **Editor footer** when the session being edited has practice on more than one day, worked out as `PracticeDay.group([session], in: .autoupdatingCurrent).count > 1`: no new core code, and it follows the edit live, so dragging an end past midnight shows the note at once. Shown where the overlap warning shows, above it when both apply. Proposed wording (Q2): "This session runs past midnight, so History lists it on each day it touches. Changes here change every row."
- **Delete dialog**, from the swipe and from the editor, when the same is true: the message "It's listed on two days. Both go." under "Delete this session?". For a session over several midnights: "It's listed on more than one day. All its rows go." (Q2; or one wording for both.)
- A `SessionEdit.preview(crossing:)` and a History preview with a crossing session, so you see both.

## 4. The PR sequence

Production lines leave out tests, docs and the String Catalog, as CLAUDE.md counts them. Branch `his-1-session-across-midnight`.

| # | Title | Production | With tests and strings | Tier | Blocked on |
|---|---|---|---|---|---|
| 1 | `feat(HIS-1): Show a session that crosses midnight on each day it touches` | ~55 | ~235 | 1 | Q1, Q3, Q5 |
| 2 | `feat(SES-5): Say that a change to a session across midnight changes all its rows` | ~20 | ~50 | 1 | Q2 |

Each leaves the app correct: after PR 1 the rows, headers, week, widget and reminder agree with each other; PR 2 adds the explanation. There's no step in which totals disagree with rows, because the core change that splits the days is the same one that totals them. If you settle Q2 with this plan, one PR of ~75 production lines is the cheaper path, and I'd take it.

### PR 1 (~55)

Files:
- `Packages/PianismCore/Sources/PianismCore/PracticeSession.swift` (~3): `practiced(from:before:)`.
- `PracticeDay.swift` (~+25 net): `end`, `Part`, `part(of:)`, the day walk in `group`, `total` from parts; `wholeSecondsPracticed` deleted (−7); comments.
- `PracticeWeek.swift` (~3): `end` on empty days; `timeByTag` over parts.
- `PracticeTotals.swift` (1): comment.
- `Packages/PianismFeatures/Sources/PianismFeatures/History/HistoryModel.swift` (~6): the flat `sessions`; two sites read it; comment.
- `HistoryView.swift` (~8): the row from `part(of:)`; the range formatter.
- `Practice/PracticeModel.swift` (~6): `hasPracticedToday`.
- `Previews.swift` (~2): a session from 11:00 PM yesterday to 12:15 AM today in `HistoryModel.preview`, so Today's last row and Yesterday's first show the split in every History preview.
- Docs: ADR 0004's note, the decisions row, W3 (§6).

Tests:
- **Core, `PracticeDayTests`** (replacing `lateSessionCountsTowardStartDay`): "HIS-1: a session across midnight shows under both days, each with the minutes practiced in it, and the totals add the rows"; "HIS-1: a session across several midnights shows under each day it has practice in, and none for a day it was paused through" (a manual Monday-evening-to-Wednesday-morning session paused across Tuesday); "HIS-1: each row rounds its own seconds down, so a day's total equals its rows even when the session's seconds split across midnight" (the 59:58 case); "HIS-1: a part under a second gets no row"; "HIS-1: a session ending exactly at midnight shows under one day"; "HIS-1: where the clocks skip midnight, the split is at the day's first moment" (Santiago, 2027-09-05; Saturday 23:30 to Sunday 01:30 is 30 minutes each side); "HIS-1: a session across midnight on a 25-hour day" (Los Angeles, 2027-11-07).
- **Core, `PracticeSessionTests`:** "GLN-2, HIS-1: practice between two moments clips each span at both, pauses left out", including a pause across the first moment.
- **Core, `PracticeWeekTests`** (changing `otherWeeksDontCount`): "HIS-2: sessions outside the week don't count, and one across the week's first midnight counts only the minutes inside it" (keeps the Sunday 23:30 session, now expecting 30 minutes on Monday); "HIS-2: a tag's time adds a crossing session's parts, once each, so the week's by-tag times equal its total" (point 4).
- **Core, `PracticeTotalsTests`** (replacing `sessionPastMidnightCountsTowardItsStartDay`): "GLN-2: a finished session that ran past midnight counts its after-midnight minutes toward the new day" (at 00:45 the next day, `finished` is 30 minutes, not 0).
- **Features, `PracticeModelTests`:** "SET-1: a session stopped this morning that started last night counts as practice today"; "SET-1: a session paused this morning after starting last night counts as practice today"; "SET-1: a session paused through midnight counts for the minutes after it". `aSessionPausedYesterdayIsNotPractice` and `aSessionRunningPastMidnightCountsAsPractice` stay and keep passing.
- **Features, `HistoryModelTests`:** "SES-5, HIS-1: the sessions an editor keeps clear of list a session across midnight once" (the overlap found once, not twice).
- **End to end, `testASessionAcrossMidnightShowsOnBothDays`** (`PracticeTests.swift`, fixed clock, reset): the test works out the next local midnight after `start` with `Calendar.current` (the simulator uses the Mac's zone, as the comment at line 524 relies on). Launch at 11:50 PM, Start, kill; relaunch at 12:20 AM, Stop, open History: two `history.day` headers, "Today" worth "20 minutes" and "Yesterday" worth "10 minutes"; two `history.session` rows worth the same; "This week" worth "30 minutes" (Dec 31 2026 and Jan 1 2027 share a week with any first weekday, so this proves parts add, not sessions); tap the Today row, the editor's Practice time reads 30:00; Cancel; swipe-delete the Yesterday row and confirm: both rows go and Undo returns both. Screenshot "History, a session across midnight" for the PR.
- **Planted bugs** (rule 9), each with the test that catches it: the day walk stopping before the end day (`<` for `<=`) → the two-days test; `practiced(before: end)` without `from:` → the totals test (yesterday's minutes land in today); `total` adding `elapsed` → the rounding test (header ≠ rows); `timeByTag` adding sessions → the by-tag test (counted twice); `hasPracticedToday` still reading `startedAt` → the reminder test.
- `make mutate` on the changed core lines (decision 2026-10-19).

### PR 2 (~20)

Files: `SessionEditorModel.swift` (~4, `crossesMidnight`), `SessionEditorView.swift` (~7, the footer), `HistoryView.swift` (~5, the dialog's message), `Previews.swift` (~4), String Catalog (3 strings).

Tests: features "SES-5, HIS-1: the editor knows when a session has practice on more than one day, and follows the edit"; the end-to-end test above gains two assertions (the footer's identifier `editor.spans-days` is visible; the dialog's message shows). Planted bugs: `count >= 1` for `> 1` (every editor shows the footer); the footer only on the opened times, not the edited ones.

## 5. Risks, and what's permanent

Permanent: nothing. No stored field, key or format changes; a device on an older build reads the same sessions and groups them by start day until it updates, which only shows the rows differently.

- **R1. Fixture dates at midnight.** `ManualClock`, `previewNow` and the UI tests' `start` are all 2027-01-01 00:00 UTC. In a UTC zone several features fixtures start or end exactly at midnight (a session from 23:50 to 00:00:00); a zero part gets no row, so they come out as today. I checked each `HistoryModelTests` fixture; none has practice on both sides of a midnight in a UTC or US zone. A failure on the first run points at a fixture, not the rule.
- **R2. The cap test and odd zones.** `testSessionLeftRunningStopsAtTheCap` asserts a 4-hour row; the session runs 19:00 to 23:00 in New York and 00:00 to 04:00 in UTC, so it holds there. In a zone one to three hours west of UTC it would now cross midnight and split. The suite is already zone-bound (line 524's comment); I'd note it in the PR and not fix it.
- **R3. The new end-to-end test's midnight** is computed in the test process; if a CI simulator ever ran in another zone than its Mac, the day labels would be off. Same bound as R2.
- **R4. The sub-minute title** `12:00 – 12:00 AM` (§0.4). Decided, but it's the row you'll most likely want to change later.
- **R5. Rounding in the week by tag.** `timeByTag`'s whole-second test (#183) still holds, as each part is floored before it's added, and `week.total` sums the same parts.
- **R6. Past weeks shift** (§0.10). Only you have data today; worth knowing before you compare a week to memory.

## 6. Tests that change (rule 6), and W3 (rule 8)

Tests that flip, each because it pins the start-day rule:

| Test | Today | After |
|---|---|---|
| `PracticeDayTests.lateSessionCountsTowardStartDay` ("a session that runs past midnight counts toward the day it started") | One day, 60 minutes | Replaced by the two-days test: two days, 30 and 30 |
| `PracticeTotalsTests.sessionPastMidnightCountsTowardItsStartDay` ("GLN-2, ADR 0004: … counts toward the day it started") | At 00:45 the next day, `finished == 0` | `finished == 30 * 60`; renamed |
| `PracticeWeekTests.otherWeeksDontCount` ("sessions outside the week don't count toward it") | `week.total == 0`, every day empty; its `lastSunday` runs 23:30 to 00:30 into the week's Monday | `week.total == 30 * 60`, Monday has one session; renamed to say so. The brief expected two flips; this is the third. |

No features or end-to-end test flips (R1, R2). Nothing is weakened: each replacement asserts more than the test it replaces.

**W3** today checks the widget's "0m" after midnight and the running clock counting from midnight, then that it "shows today's total again once Pianism next opens". Proposed row, in PR 1:

> W3 **After midnight:** set the iPhone's time to a minute before midnight (Settings > General > Date & Time, automatic off), wait past midnight without opening Pianism. The widget shows "0m" for the new day on its own. Then again with a session running across midnight: after midnight the widget counts only the minutes since midnight. Stop it a few minutes later and open Pianism: History lists the session under Yesterday with the minutes up to midnight and under Today with the minutes since, Today's header equals the widget's figure, and the editor shows the whole session; the widget shows that total once Pianism has opened. Set the time back to automatic. The core tests "HIS-1: a session across midnight shows under both days…" and "GLN-2: a finished session that ran past midnight counts its after-midnight minutes…" cover the numbers, and `testASessionAcrossMidnightShowsOnBothDays` History's two rows; only the widget's own screen needs the device (ADR 0010).

R1 and R2 (the reminder rows) don't change: they check arrival and the widget's background Start, and `practicingTodayMovesTheReminderToTomorrow` keeps covering the rule, with the new model tests beside it.

## 7. Decisions I took without asking (say if you disagree)

- A row shows when its part is at least one whole second; under that, no row and nothing added.
- Each part rounds down on its own (§0.6).
- Midnight is the current calendar's; the stored time zone stays unused (ADR 0006).
- The reminder uses the same one-second rule as the rows.
- The ADR amendment and the decisions row go in PR 1, since PR 1 is what makes the old sentence false.
- `wholeSecondsPracticed` is deleted; the History preview gains a crossing session; the end-to-end test's shape in §4.
- Code comments and test names saying "the day it started" are reworded in PR 1.

## 8. Questions for Ed

**Answered by Ed, 2026-11-05:** Q1 each row shows its own span. Q2 the recommended wording. Q3 any row skips the reminder, tiny parts included. Q4 left to HIS-3's plan. Q6 one PR. Q5 (the three test flips and W3) goes with his approval of the plan.

Blocking PR 1:

1. **Row title:** each row shows its own span, `11:30 PM – 12:00 AM` under Yesterday and `12:00 – 12:30 AM` under Today (recommended: a row then reads true on its own, and the editor shows the whole), or both rows show the whole session's `11:30 PM – 12:30 AM` beside different minutes, which needs the footer to make sense of?
2. **Wording** (needed for PR 2; settling it now lets both go in one PR):
   - Editor footer: "This session runs past midnight, so History lists it on each day it touches. Changes here change every row." (recommended), or shorter: "This session is listed on two days. A change here changes both." (wrong for a manual entry over several days).
   - Delete dialog message: "It's listed on two days. Both go." with "It's listed on more than one day. All its rows go." for several (recommended), or one wording: "It's listed on more than one day. All its rows go."
3. **The reminder:** a few seconds past midnight count as today's practice and skip today's reminder (recommended: it's the same rule as History's rows, and the reminder is a nudge, not a judge, per P6). Or keep the reminder on the session's start day, which today's code does, and accept that History and the reminder disagree on a late night?
4. **HIS-3:** settle now that "practiced" means a day with a row (recommended, one rule everywhere), or leave the threshold to HIS-3's plan?
5. **Tests:** approve the three flips in §6 and the W3 rewrite.
6. **One PR or two?** One of ~75 production lines if Q2 is settled now (recommended); otherwise PR 1 goes first and PR 2 waits on the wording.

## 9. Not verified

- Nothing was built or run; line counts come from reading main.
- The exact string `Date.IntervalFormatStyle` gives for a span inside one minute (`12:00 – 12:00 AM` is my reading of the format; the end-to-end test asserts values, not titles).
- Whether `Charts` draws a bar for a day whose only session is a tail of a few seconds (a bar of height 0.1 minutes); it should, and the AX5 preview will show it.
- The time zone of the CI Macs, beyond line 524's "a whole number of hours from UTC".

### Critical files for implementation

- /Users/edward_karabinus/Developer/Pianism/Packages/PianismCore/Sources/PianismCore/PracticeDay.swift — `group` walks days; `end`, `Part`, `part(of:)`; `total` from parts; `wholeSecondsPracticed` goes.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismCore/Sources/PianismCore/PracticeSession.swift — `practiced(from:before:)`, the one new primitive.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismCore/Sources/PianismCore/PracticeWeek.swift — `timeByTag` over parts; `end` on empty days.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/History/HistoryModel.swift — the flat `sessions` for `edit(id:)` and `otherSessions(at:)`.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/History/HistoryView.swift — the row from `part(of:)`; PR 2's dialog message.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/Practice/PracticeModel.swift — `hasPracticedToday`.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismFeatures/Sources/PianismFeatures/History/SessionEditorModel.swift and SessionEditorView.swift — PR 2's `crossesMidnight` and footer.
- /Users/edward_karabinus/Developer/Pianism/Packages/PianismCore/Tests/PianismCoreTests/PracticeDayTests.swift, PracticeWeekTests.swift, PracticeTotalsTests.swift — the three flips and the new cases.
- /Users/edward_karabinus/Developer/Pianism/AppUITests/PracticeTests.swift — `testASessionAcrossMidnightShowsOnBothDays`, beside `testFinishedSessionAppearsInHistory` (line 589) and the `launch` helper (line 1585).
- /Users/edward_karabinus/Developer/Pianism/docs/adr/0004-synced-data-model.md, docs/decisions.md, docs/device-checklist.md — the amendment, the row, W3.
