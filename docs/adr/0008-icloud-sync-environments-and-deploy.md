# 8. History syncs through CloudKit, with Debug and Release builds kept apart, and one checked deploy

- Status: accepted
- Date: 2026-10-20
- Amends: [ADR 0004](0004-synced-data-model.md), [ADR 0006](0006-schema-v1-before-deploy.md)

## Context and problem statement

ADR 0004 syncs finished sessions and tags through the private database of a CloudKit container,
`iCloud.com.edkarabinus.Pianism`. CloudKit has two environments. Development builds its schema from
whatever records arrive and can be reset. Production gets the schema only when the owner deploys it,
and from then on no record type or field can be renamed, removed or change type. A field missing
from the deploy makes every record that sets it fail to sync until a later deploy adds it.

So the deploy can't be undone, and anything that reaches Development before it, such as the sync
check's `CD_SpikeNote`, would be deployed too. The owner's decisions are on #15 (2026-10-20).

## Considered options

1. **Every build on Development until launch.** Simpler at first, but real history would sit in an
   environment that gets reset, and the switch to Production would happen on users' devices.
2. **Debug builds on Development, Release builds on Production.**
3. **Our own sync engine (CKSyncEngine),** to keep history on a device when its iCloud account signs
   out. Much more code, for a case the owner accepts.

## Decision

Option 2.

- **Environments.** `com.apple.developer.icloud-container-environment` comes from the xcconfigs:
  Debug uses `Development` and Release uses `Production`, even when Xcode installs a Release build.
  Debug syncs only when launched with `PIANISM_SYNC=1`, as the end-to-end tests are.
- **The owner's iPhone runs Release builds only.** Pianism is deleted and installed again before its
  first syncing build, so no store moves between environments.
- **Pushes.** The `remote-notification` background mode is Pianism's only one (NFR-9, as amended), so
  changes from other devices arrive within seconds.
- **Signing out.** When a device signs out of iCloud, or turns iCloud off for Pianism, Apple's sync
  removes the synced history from that device. It comes back on sign-in.
- **The deploy,** done once for schema v1 and the same way for any later change:
  1. The snapshot test in `HistoryStoreFormatTests` is green on main. It lists every attribute as
     CloudKit will see it, and checks that `docs/cloudkit/schema-v1-fields.txt` names each one.
  2. Development lists only `Users`, or is reset (`xcrun cktool reset-schema`).
  3. A Debug build launched with `PIANISM_INIT_CLOUDKIT_SCHEMA=1` on a simulator signed into iCloud
     creates the schema (`initializeCloudKitSchema()`, as Apple's sample does). If iCloud takes over
     30 seconds, Core Data gives up (error 134060) and the app stops; launching it again is safe.
  4. `xcrun cktool export-schema` of Development, reduced by `scripts/cloudkit-fields.sh`, matches the
     fields file. Each difference is explained on #15, and a reviewer signs off. Core Data adds
     `CD_moveReceipt` (and its `_ckAsset`) to every mirrored record type, so the file lists it
     though no attribute maps to it.
  5. Two signed-in simulators sync real records, with every field set, and the export still matches.
  6. The owner deploys in CloudKit Console. Production's export must equal Development's, and is kept
     as `docs/cloudkit/schema-v1.ckdb`.
- **Development holds nothing experimental before any deploy.** A spike uses another container, or
  Development is reset first.

## Consequences

- After the deploy, the schema can only gain fields. The snapshot test fails on any change to the
  model, so none happens by accident.
- With `note` encrypted (ADR 0006), resetting a person's encrypted iCloud data, which people do after
  losing every device and passcode, may delete all of Pianism's synced history, not only the notes.
  This is unverified. The owner accepts it: losing data is that reset's purpose, and a device that
  still has Pianism should upload its copy again.
- CI never signs into iCloud. Test simulators stay signed out, and the simulators that check sync are
  named so the tests can't pick them (`docs/device-checklist.md`).
