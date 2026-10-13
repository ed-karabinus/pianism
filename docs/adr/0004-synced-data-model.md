# 4. Finished sessions and tags in SwiftData, mapped to core values and synced through CloudKit

- Status: proposed
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
that isn't a row? How do we prevent duplicates without unique constraints? How do we evolve the
schema?

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
IDs, a note and a source as those features land), `Tag`, and `TagID`. It also defines two ports
the adapter implements:

- `SessionHistory`: save, which inserts or updates by ID; sessions in a date range; delete.
- `TagLibrary`: all tags; add, rename and archive.

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
| `createdAt`, `modifiedAt` | `Date`, `.distantPast` | |

**Tags by ID, with no relationships.** Built-in skills have fixed IDs in the core, such as
`skill.scales`. User tags have UUIDs. A session stores the IDs of its tags, so both kinds take the
same path, and a relationship never has to point at a constant. With no relationships, sync can
deliver records in any order: a session that arrives before its tag shows the tag once it arrives.
Since tags are archived rather than deleted, references don't dangle. If an ID can't be resolved,
the tag is left out, and a session with no tags left shows "Untagged" (TAG-2).

**No duplicates without unique constraints.** Every save is an upsert: fetch by `id`, update if
found, insert otherwise. Moving an ended session out of the running-session file is
`history.save(session)` followed by clearing the file. If the app dies in between, the next launch
saves it again, and the upsert makes that harmless. Reads still drop any duplicate `id` and keep
the latest `modifiedAt`, in case sync ever delivers one.

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
  see a `@Model` type.
- Good: saving the same session twice is harmless, which closes the crash window ADR 0003 left
  between the file and the store.
- Good: built-in skills can't be duplicated by sync, and their names can be localized and renamed
  freely.
- Bad: no `@Query` in views. View models fetch through the ports and refetch when the store reports
  a change, local or synced. That is a little more code than SwiftData's defaults.
- Bad: "sessions for this piece" (HIS-4, M4) filters `tagIDs` in memory, because SwiftData
  predicates can't look inside an array attribute. At a few thousand sessions, that is milliseconds.
  The NFR performance test will measure it.
- Bad: two devices offline can each create a piece with the same name, and both are kept. Merging
  tags is a possible later feature, which would rewrite references.
- Out of scope: PRO-2's count of free auto-logged sessions isn't derived from history, because
  deleting sessions would reset it. It's decided with Purchases in M4.
- To verify with SYN-1 (#15): sync between two real devices, and the CloudKit dashboard's schema
  check before the first production deploy. Neither can run in CI.
