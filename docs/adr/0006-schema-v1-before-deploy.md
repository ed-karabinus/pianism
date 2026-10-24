# 6. Schema v1 gains a record version, a time zone and a deleted mark before it ships

- Status: accepted; the deploy by [ADR 0008](0008-icloud-sync-environments-and-deploy.md); the
  `version` rule's `source` example by [ADR 0009](0009-what-a-midi-session-stores.md)
- Date: 2026-10-15
- Amends: [ADR 0004](0004-synced-data-model.md)

## Context and problem statement

ADR 0004 set schema v1 for finished sessions and tags, and nothing is built on it yet. Once a schema
reaches CloudKit's production environment, "the record types and their fields are immutable and
exist for all time"
([Apple](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)).
TestFlight builds use the production environment ([Apple
DTS](https://developer.apple.com/forums/thread/819507)), so v1 freezes when it's promoted, which has
to happen before the first TestFlight build that syncs (SYN-1, milestone M1).

An independent review of ADR 0004, checked against Apple's documentation, found three gaps that only
v1 can close:

- **Sessions don't record their time zone.** After travel or a time zone change, the day a session
  belongs to can't be recovered.
- **Older app versions overwrite newer data.** An unknown value reads as the default (ADR 0004,
  "Schema evolution"), and saving writes the whole record. Editing a note in an old version turns a
  MIDI session into a timer session. Old versions stay installed indefinitely.
- **A deleted session can come back.** A device that still holds the session saves it after the
  delete arrives; the upsert finds no row and inserts one.

## Considered options

For older versions:

1. **Keep what you don't understand:** carry unknown values through the core, and write only the
   fields an edit changed.
2. **A `version` on every record,** as Apple recommends "from the outset": an app changes only the
   records whose version it knows.

For deletion:

1. **Remove the row,** as in ADR 0004.
2. **Mark it deleted** with `deletedAt`, and keep a record with no content.

## Decision

Option 2 for both, plus the changes below.

**Schema v1 changes.**

| Record | Change | Field | Type, default | Notes |
| --- | --- | --- | --- | --- |
| both | add | `version` | `Int`, `1` | See "Records from newer versions" |
| `SessionRecord` | add | `timeZoneID` | `String`, `""` | Such as `America/Los_Angeles`. See "Time zone" |
| `SessionRecord` | add | `deletedAt` | `Date?`, `nil` | See "Deletion" |
| `SessionRecord` | remove | `practicedSeconds` | | The core totals sessions from their timestamps. Nothing would read a stored copy, and a sync merge could make it disagree |
| `SessionRecord` | change | `id` | `UUID`, a new UUID | CloudKit needs a default, and ADR 0004 gave none |
| `SessionRecord` | specify | `pauses` | `Data`, empty | JSON, `{"pauses": [...]}`, dates in `Date`'s own encoding (seconds since 2001), which round-trips exactly. An object, so it can gain keys. Empty means no pauses |
| `SessionRecord` | specify | `note` | `String`, `""` | Encrypted in iCloud (`.allowsCloudEncryption`). See "Before the CloudKit deploy" |
| `TagRecord` | add | `deletedAt` | `Date?`, `nil` | See "Before the CloudKit deploy" |
| `TagRecord` | specify | `name`, `composer` | `String`, `""` | Encrypted in iCloud, as `note` is. See "Before the CloudKit deploy" |
| `SessionRecord` | change | `tagIDs` | `Data`, empty | A JSON array of strings, such as `["skill.scales"]`. Empty means none. See "Before the CloudKit deploy" |

Corrected 2026-10-15 by the first store code: the `pauses` row first said `.secondsSince1970`. That
loses the last bit of a fractional time, so a session stopped while paused could read back with its
pause ending after the session; the test "a session stopped while paused comes back exactly" catches
it. "Duplicates from this device" first said saves go through one `ModelActor`; a lock does the same
without making the synchronous `SessionHistory` port async.

**Before the CloudKit deploy** (amended 2026-10-20 by the owner, for SYN-1). The deploy freezes every
record type and field, so four changes come first:

- `note` is encrypted in iCloud, as the only field holding the user's own words. A field's encryption
  can't change once deployed, either way. Tag names and composers stay plain.
  Amended 2026-10-21 by the owner (#15): tag names and composers are encrypted too. People type
  anything into them, and only encrypted fields and assets become end-to-end under Advanced Data
  Protection.
  IDs, kinds, dates and tag IDs stay plain, so CloudKit Console can still show what synced.
- `TagRecord` gains `deletedAt`, under the same rule as sessions: an ID with any deleted copy doesn't
  show. Tags are only archived today; with the field there now, a version that deletes them won't
  leave nameless tags showing in this one. A session keeps a deleted tag's ID, as it keeps one this
  device hasn't synced yet, and the screen leaves it out.
- `tagIDs` becomes JSON, like `pauses`, rather than `[String]`. SwiftData stored the array as a keyed
  archive (`NSSecureUnarchiveFromData`) whose bytes it chooses, and devices on different iOS versions
  share these records. Core Data can't convert the type, so stores written before this change don't
  open: only the owner's iPhone had history, and it is reinstalled. The fixture stores were replaced
  once, and the one from before tags was retired.
- iCloud keeps `startedAt` and `endedAt` to the millisecond but `pauses` exactly, so a pause can stick
  out of a synced session by less than a millisecond. Reading clamps each pause into the session;
  without that, a session stopped while paused would be hidden on the other device. Any pause outside
  the session is cut to it, as an edit does, but a pause that ends up empty is kept: a session paused
  and stopped at the same instant holds one, and dropping it would make `save` refuse that session.
  "Round-trips exactly" holds on one device only.

**Records from newer versions.** `version` starts at 1. A release raises it when it adds a field, or
a stored value, that an older app would lose by saving, whether or not the schema changes. Every
save writes the app's own `version`. An app edits, deletes, archives or merges only records whose
`version` is at most its own. It shows the others read-only and asks the user to update, so the
values the ports return say whether they can be changed. An unknown value reads as the default, for
display only. A tag ID this device can't resolve yet stays in the record and is left out only on
screen.
Amended 2026-10-23 by [ADR 0009](0009-what-a-midi-session-stores.md) (#120): the example "such as a
new `source`" is removed. An older app's edit never loses a source: builds before #122 never write
it, and builds since keep a value they don't know, so a new source needs no bump.

Option 1 is rejected because every later version would have to carry every unknown field without
loss, and no test can check a version that doesn't exist yet. Option 2 is one comparison.

**Time zone.** It is recorded now because a session saved without it can never get it back.
`PracticeSession` takes the zone when it starts, from an injected source like the clock (E3), so ADR
0003's running-session file carries it, and a session moved to the store later keeps the zone it
started in. A manual entry takes the zone where it was made. Editing the start or end
keeps the zone. History still groups by the device's current time zone (ADR 0004). Grouping by the
recorded zone is a later product decision, made with a reason such as a streak feature. This is a
deliberate exception to "nothing without a caller" in `CLAUDE.md`.

**Deletion.** Deleting sets `deletedAt` and `modifiedAt` and clears `note` and `tagIDs`, so the
user's words are gone. A save to an `id` that has a deleted record changes nothing, which is what
stops a session coming back. An `id` with any deleted record reads as deleted, even if a duplicate
isn't. The adapter hides deleted sessions in one place. SES-5's five-second undo happens before the
delete reaches the store. Records are never purged, because removing a row syncs as a delete and
reopens the gap.

Option 1 is rejected because of that gap, and because adding the mark later would leave older
versions showing deleted sessions: the reason ADR 0004 ships `mergedInto` in v1.

**Duplicates from this device.** With no unique constraint, two saves racing on this device can both
insert, and CloudKit won't merge them: it names a record after Core Data's object ID, not after `id`
([Apple](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)).
The adapter saves one at a time, and delete marks every record with that `id`.

**Sync merges.** Apple describes CloudKit's conflict handling as "last writer wins" (WWDC 2019), so
an edit made on another device before sync can be lost; SYN-1 tests this on two devices. If it shows
that two edits' fields can mix, reading gets a rule for that then, with no schema change.

**Schema evolution** (replaces ADR 0004's rename rule). Migration stages are lightweight only. No
stage rewrites records: every device would run it and export every record it touched. Apple doesn't
document custom stages for CloudKit stores, and developers report them crashing or never running
with CloudKit since iOS 17.4 ([forums](https://developer.apple.com/forums/thread/744491)). A rename
is a new field written alongside the old one, read with a fallback to the old one.

**Before the first production deploy.** A field nothing has written yet, such as `deletedAt` or
`targetTempo`, which default to nil, may be missing from the development schema when it's promoted.
Following [Apple's SwiftData
guide](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices),
a Debug build creates the full schema with
`NSPersistentCloudKitContainer.initializeCloudKitSchema()`, which uploads "a representative value
for every field". Apple's sample runs this on every Debug launch; ours runs only with the environment
variable `PIANISM_INIT_CLOUDKIT_SCHEMA=1`, because the simulators in CI have no iCloud account. The
export is then compared with these tables, as [ADR 0008](0008-icloud-sync-environments-and-deploy.md)
sets out. This is part of SYN-1, before the first TestFlight build.

**Smaller fixes.**

- Undoing a tag merge clears `mergedInto` and also unarchives the tag.
- Each fixture store sets every field to a value other than its default, so a change in how we
  encode `tagIDs` or `pauses` fails a test.

## Consequences

- Good: the three gaps close before they become permanent, for three new fields.
- Good: an older version can't damage newer data, and the rule is one comparison rather than a
  discipline every later version has to keep.
- Bad: on an older version, records a newer one wrote are read-only until the user updates.
- Bad: a record this version can't rebuild at all, newer or damaged, can't be shown, even read-only.
  History counts such sessions and asks the user to update (HIS-1, #65, 2026-10-20).
- Bad: every deleted session leaves an empty record of a few bytes, forever.
- Bad: `timeZoneID` is stored before anything uses it.
- Bad: when two devices edit the same session before syncing, one edit can be lost. SYN-1 will show
  how CloudKit resolves it.
- The deadline moves: schema v1 freezes before the first TestFlight build that syncs (SYN-1, M1),
  not at the App Store submission.
