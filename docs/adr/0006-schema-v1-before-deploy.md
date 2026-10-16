# 6. Schema v1 gains a record version, a time zone and a deleted mark before it ships

- Status: accepted
- Date: 2026-10-15
- Amends: [ADR 0004](0004-synced-data-model.md)

## Context and problem statement

ADR 0004 set schema v1 for finished sessions and tags, and nothing is built on it yet. Once a
schema reaches CloudKit's production environment, "the record types and their fields are immutable
and exist for all time" ([Apple](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)).
TestFlight builds use the production environment
([Apple DTS](https://developer.apple.com/forums/thread/819507)), so v1 freezes with the first
TestFlight build that syncs, before the App Store release.

An independent review of ADR 0004 (Fable 5.1, 2026-10-15), checked against Apple's documentation,
found three gaps that only v1 can close:

- **Sessions don't record their time zone.** After travel or a time zone change, the day a
  session belongs to can't be recovered.
- **Older app versions overwrite newer data.** An unknown value reads as the default (ADR 0004,
  "Schema evolution"), and saving writes the whole record. Editing a note in an old version
  turns a MIDI session into a timer session. Old versions stay installed indefinitely.
- **A deleted session can come back.** A device that still holds the session saves it after the
  delete arrives; the upsert finds no row and inserts one.

It also found rules around the schema that Apple's documentation doesn't support.

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
| `SessionRecord` | add | `timeZoneID` | `String`, `""` | Such as `America/Los_Angeles`: where the session started, or where a manual entry (SES-5) was made |
| `SessionRecord` | add | `deletedAt` | `Date?`, `nil` | See "Deletion" |
| `SessionRecord` | remove | `practicedSeconds` | | The core totals sessions from their timestamps. Nothing would read a stored copy, and a sync merge could make it disagree |
| `SessionRecord` | change | `id` | `UUID`, a new UUID | CloudKit needs a default, and ADR 0004 gave none |
| `SessionRecord` | specify | `pauses` | `Data`, empty | JSON, `{"pauses": [...]}`, dates as `.secondsSince1970`. An object, so it can gain keys |

**Records from newer versions.** `version` is the schema version of the app that last wrote the
record. A later schema raises it when it adds a field or value that an older app would lose by
saving. Every app shows every record, but changes only records whose `version` it knows; editing a
newer one asks the user to update. An unknown value still reads as the default, but only for
display. A tag ID this device can't resolve yet stays in the record and is left out only on
screen.

Option 1 is rejected because every later version would have to carry every unknown field without
loss, and no test can check a version that doesn't exist yet. Option 2 is one comparison.

**Time zone.** It is recorded now because a session saved without it can never get it back.
History still groups by the device's current time zone (ADR 0004). Grouping by the recorded zone
is a later product decision, made with a reason such as a streak feature. This is a deliberate
exception to "nothing without a caller" in `CLAUDE.md`.

**Deletion.** Deleting sets `deletedAt` and clears `note` and `tagIDs`: the user's words are gone,
and only the ID, the times and the mark remain. The adapter hides deleted sessions in one place.
Saving over a deleted record leaves it deleted, which is what stops a session coming back. SES-5's
five-second undo happens before the delete reaches the store. Records are never purged, because
removing a row syncs as a delete and reopens the gap.

Option 1 is rejected because of that gap, and because adding the mark later would leave older
versions showing deleted sessions: the reason ADR 0004 ships `mergedInto` in v1.

**Duplicates from this device.** CloudKit names a record after Core Data's object ID, not after
`id` ([Apple](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)),
so two saves racing on this device can create two records. The adapter saves through one
`ModelActor`, and delete marks every record with that `id`.

**Sync merges.** Apple describes CloudKit's conflict handling only as "last writer wins" (WWDC
2019). In one developer's experiment, edits to different fields of a record weren't combined: the
later save replaced the earlier one whole ([forums](https://developer.apple.com/forums/message/382355)).
Either way, an edit made on another device before sync can be lost; SYN-1 tests this on two
devices. Reading a record applies SES-5's rule for pauses outside a moved start or end, so a record
stays valid even if CloudKit does mix fields.

**Schema evolution** (replaces ADR 0004's rename rule). Migration stages are lightweight only. No
stage rewrites records: every device would run it and export every record it touched. Apple
doesn't document custom stages for CloudKit stores, and developers report them crashing or never
running with CloudKit since iOS 17.4 ([forums](https://developer.apple.com/forums/thread/744491)).
A rename is a new field written alongside the old one, read with a fallback to the old one.

**Before the first production deploy.** A field nothing has written yet, such as `mergedInto`,
may be missing from the development schema when it's promoted. Following
[Apple's SwiftData guide](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices),
a Debug build creates the full schema with `NSPersistentCloudKitContainer.initializeCloudKitSchema()`,
which uploads "a representative value for every field". Apple's sample runs this on every Debug
launch; ours runs only with a launch argument, because the simulators in CI have no iCloud account.
The CloudKit dashboard is then compared with these tables. This is part of SYN-1, before the first
TestFlight build.

**Smaller fixes.**

- Undoing a tag merge clears `mergedInto` and also unarchives the tag.
- Each fixture store sets every field to a value other than its default, so a change in how
  SwiftData stores `tagIDs` or `pauses` fails a test.

## Consequences

- Good: the three gaps close before they become permanent, for three new fields.
- Good: an older version can't damage newer data, and the rule is one comparison rather than a
  discipline every later version has to keep.
- Bad: on an older version, records a newer one wrote are read-only until the user updates.
- Bad: every deleted session leaves an empty record of a few bytes, forever.
- Bad: `timeZoneID` is stored before anything uses it.
- Bad: when two devices edit the same session before syncing, one edit can be lost. SYN-1 will
  show how CloudKit resolves it.
- The deadline moves: schema v1 freezes with the first TestFlight build that syncs (M3), not with
  the App Store submission.
