# 4. Finished sessions and tags in SwiftData, mapped to core values and synced through CloudKit

- Status: accepted; schema v1 and some rules amended by [ADR 0006](0006-schema-v1-before-deploy.md); sync
  environments and the deploy by [ADR 0008](0008-icloud-sync-environments-and-deploy.md)
- Date: 2026-10-13
- Issue: #25

## Context and problem statement

Finished sessions (HIS-1, SES-5) and the user's pieces and skills (TAG-1 to TAG-3) must persist,
work offline and sync through the user's private iCloud with no sign-in (SYN-1). The spec fixes the
stack, SwiftData with CloudKit, and CloudKit brings constraints:

- Every attribute is optional or has a default. There are no unique constraints, and every
  relationship is optional.
- Once the schema is deployed to CloudKit production, it can only grow. An attribute or model can
  never be renamed, removed or change type.

Two earlier decisions shape the answer. The running session lives in a file, and only the app moves
it into the synced store (ADR 0003). Built-in skills are code constants, never seeded rows, so sync
can't duplicate them (TAG-1). Engineering principle E1 keeps SwiftData out of the core.

So: what do sessions and tags look like in the store? How does a session refer to a built-in skill
that isn't a row? How do we prevent duplicates without unique constraints, and merge the ones sync
can't prevent? How do we evolve the schema?

## Considered options

1. **`@Model` types everywhere:** the core and the views use SwiftData models directly, with
   `@Query` in views.
2. **`@Model` types only in `PianismPersistence`, mapped to core values.** Sessions refer to tags
   by ID.
3. **As option 2, but sessions link to user tags through a SwiftData relationship,** with a
   separate list for built-in skills.
4. **Each session as one encoded blob** in a single attribute.

## Decision

Option 2.

**Core values and ports.** The core owns plain values: `PracticeSession` (from #18, which gains tag
IDs, a note and a source as those features land), and `Tag`. It also defines two ports
the adapter implements:

- `SessionHistory`: save, which inserts each ID once; sessions in a date range; delete.
- `TagLibrary`: all tags; add, rename, archive and merge.

Both ports also report when anything they hold changes, on this device or from iCloud, so view
models know when to fetch again.

Amended 2026-10-16 by TAG-1: a tag's ID is `Tag.ID`, a `String`, rather than a separate `TagID`
type, since a session stores built-in and user tag IDs alike as strings. Both adapters share one
SwiftData store, `HistoryStore`, so a session and the tags it names live, and later sync, together.

Grouping by day, day totals and week totals are pure core functions over values (HIS-1, HIS-2). They
are tested on Linux, including time zones and daylight-saving changes. **A session counts toward
the day it started.**

**Store models (schema v1, in `PianismPersistence`):**

| `SessionRecord` | Type, default | Notes |
| --- | --- | --- |
| `id` | `UUID` | The `PracticeSession` ID; identity across devices |
| `startedAt`, `endedAt` | `Date`, `.distantPast` | |
| `pauses` | `Data`, empty | Encoded `[Pause]`; read and written as a whole |
| `practicedSeconds` | `Double`, `0` | Derived from the timestamps on every save, so totals are a sum |
| `tagIDs` | `[String]`, `[]` | See "Tags by ID" |
| `note` | `String`, `""` | SES-5 |
| `source` | `String`, `"timer"` | `timer`, `manual` (SES-5) or `midi` (MIDI-1) |
| `modifiedAt` | `Date`, `.distantPast` | Breaks ties between duplicates |

| `TagRecord` | Type, default | Notes |
| --- | --- | --- |
| `id` | `String`, `""` | A lowercase UUID |
| `kind` | `String`, `"piece"` | `piece` or `skill` |
| `name` | `String`, `""` | |
| `isArchived` | `Bool`, `false` | Tags are archived, never deleted |
| `composer` | `String`, `""` | TAG-3 |
| `targetTempo` | `Int?`, `nil` | TAG-3, in BPM |
| `mergedInto` | `String`, `""` | The ID of the tag this one was merged into. See "Duplicate tags" |
| `createdAt`, `modifiedAt` | `Date`, `.distantPast` | |

**Tags by ID, with no relationships.** Built-in skills have fixed IDs in the core, such as
`skill.scales`. User tags have UUIDs. A session stores the IDs of its tags, so both kinds take the
same path, and a relationship never has to point at a constant. With no relationships, sync can
deliver records in any order: a session that arrives before its tag shows the tag once it arrives.
Since tags are archived rather than deleted, references don't dangle. If an ID can't be resolved,
the tag is left out, and a session with no tags left shows "Untagged" (TAG-2).

**No duplicates without unique constraints.** Saving a finished session inserts it only if no
record has its `id`, and stamps `modifiedAt`. Moving an ended session out of the running-session
file is `history.save(session)` followed by clearing the file. If the app dies in between, the next
launch saves it again, and finding the record makes that harmless. Reads still drop any duplicate
`id` and keep the latest `modifiedAt`, in case sync ever delivers one.

Amended 2026-10-16, after a review of every ADR against the code: saving was an upsert, so a stale
copy, such as one left in the outbox (ADR 0007) after its removal failed, could replace a later
edit. Saving now never replaces a record; editing (SES-5) gets its own path, which checks `version`
(ADR 0006). Reading also leaves out, and logs, a record it can't rebuild, so one bad record can't
hide the whole history.

**Duplicate tags are merged by alias, never by rewriting sessions.** IDs can't stop two devices
from each adding "Ballade No. 1" before either has synced, and sync can take minutes even online.
So duplicates are made rare, then recoverable:

- Adding a tag whose name matches an existing tag of the same kind, ignoring case and accents,
  offers the existing tag instead, including archived ones. That leaves only a race between
  devices.
- A merge sets the duplicate's `mergedInto` to the kept tag's ID and archives it. Sessions are
  never touched. A pure core function resolves every tag ID by following `mergedInto` to the end of
  the chain, so a session tagged with either ID counts toward the kept tag, once.
- Rewriting the sessions' `tagIDs` instead would be unsafe under sync. A device that hasn't
  received the merge keeps tagging new sessions with the old ID, and each rewritten session is a
  write that can collide with an edit made on another device. An alias covers both cases, and
  clearing `mergedInto` undoes the merge.
- Two devices can merge the same pair in opposite directions, which makes a cycle. Resolution then
  keeps the tag in the cycle created first, with ties broken by ID, so every device agrees without
  coordinating. If the kept tag hasn't synced yet, the duplicate shows as itself until it arrives.

`mergedInto` and its resolution ship in schema v1, before any merge screen exists, so every
installed version understands a merge made by a later one. Deriving tag IDs from names was
rejected: it would merge racing adds by itself, but only on exact names. It would also silently
join two different pieces: rename "Ballade" to "Ballade No. 1", add a new "Ballade", and both
pieces share an ID their sessions can never be split from. A visible duplicate can be merged and
unmerged; pieces joined by a shared ID can't be separated.

**Schema evolution.** The schema is a `VersionedSchema` with a `SchemaMigrationPlan` from v1, even
with a single version.

- New attributes are always optional or defaulted. Nothing is renamed or removed: a rename is a new
  attribute plus a migration.
- `kind` and `source` are stored as strings. An unknown value, such as one synced from a newer app
  version on another device, reads as the safe default rather than failing.
- Every schema version that ships saves a fixture store to `PianismPersistence`'s tests. Each test
  run opens every fixture with the current model, as the spec's testing table requires.

**The store belongs to the app process.** The widget (GLN-2) doesn't open it. The app writes a
small summary file to the App Group, with finished seconds per day for the last 7 days, whenever it
saves. The widget adds the running session from ADR 0003's file to show today's total. That keeps
one process on the CloudKit-mirrored store.

Option 1 is rejected because it puts SwiftData into the core (E1, ADR 0001). Grouping and totals
would then be testable only on Apple platforms, through a model container. Option 3 needs two code
paths for tags, and relationship records can sync out of order. CloudKit makes relationships
optional anyway, so they add no integrity. Option 4 rules out date predicates, which day and week
queries need, and makes every record opaque in the CloudKit dashboard.

## Consequences

- Good: day, week and per-piece rules stay in the Linux-tested core. Views and view models never
  see a `@Model` type: they hold `Sendable` values, so nothing tied to a `ModelContext` crosses an
  actor under Swift 6's strict concurrency, and previews and view-model tests need no container.
- Good: storage can change behind the ports. If SwiftData's CloudKit sync proves unreliable,
  Core Data or `CKSyncEngine` can replace it without touching views or rules.
- Good: saving the same session twice is harmless, which closes the crash window ADR 0003 left
  between the file and the store.
- Good: built-in skills can't be duplicated by sync, and their names can be localized and renamed
  freely.
- Bad: no `@Query` in views, so the app tracks changes itself, which `@Query` would do for free.
  The ports publish a "changed" signal for saves made anywhere in the app and for records imported
  from iCloud, read from SwiftData's history. Each list's view model refetches its date range when
  it fires. That's about 200 lines plus tests, but lines aren't the real cost: if the signal misses
  a change, a screen shows stale data. Local saves are covered by an integration test with two
  containers on one store, and an end-to-end test that stops a session and sees it in history.
  iCloud imports can only be checked on two real devices (SYN-1). If that signal proves
  unreliable, a list can fall back to `@Query` in its view, mapping records to core values before
  any rule runs. The core doesn't change.
- Bad: "sessions for this piece" (HIS-4, M4) filters `tagIDs` in memory, because SwiftData
  predicates can't look inside an array attribute. At a few thousand sessions, that is milliseconds.
  The same pass resolves merged tags. The NFR performance test will measure it.
- Bad: two devices that add the same piece before syncing still get two pieces, until the user
  merges them. The merge screen is a separate story, proposed as TAG-4 alongside HIS-4 in M4. Until
  then, there is no per-piece view for the split to show in, and the piece picker shows the name
  twice.
- Out of scope: PRO-2's count of free auto-logged sessions isn't derived from history, because
  deleting sessions would reset it. It's decided with Purchases in M4.
- To verify with SYN-1 (#15): sync between two real devices, and the CloudKit dashboard's schema
  check before the first production deploy. Neither can run in CI.
