# Before a CloudKit deploy, only Debug's data is cleared

Settled on 2026-11-10, the owner's pick.

A deploy's step 2 clears Debug's history and outbox on each device with a Debug launch that sets
`PIANISM_CLEAR_DEBUG_DATA=1`. It deletes `Application Support/Debug` and nothing else: the settings and the running
session stay. The app is never deleted on a device that also runs a Release build.

**Why:** on the owner's iPhone, Debug and Release are one app. Deleting it would take the real history stored there,
and `PIANISM_RESET=1`, which the tests use, also clears the settings the two builds share. See
[ADR 0008](../adr/0008-icloud-sync-environments-and-deploy.md) and [ADR 0013](../adr/0013-nested-tags.md).
