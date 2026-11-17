# The free piano sessions may read high before a reinstall's first sync

Settled on 2026-11-16, the owner's pick (device check S8).

The free 5 count every session a piano started on the iCloud account, deleted ones included, so a reinstall can't
reset them (PRO-2, ADR 0012). Right after a reinstall, History is empty until iCloud brings it back, so for those
seconds Practice says "5 free piano sessions left", then drops to the real count. On the owner's phone it read 5, then 1
a few seconds later. A piano session started in that window would start even with none left.

**Why:** it takes a reinstall and playing within seconds of opening the app, and a session started then still counts
once it's saved. The app can't reliably tell when iCloud's first sync after an install has finished, so it can't wait
for it.

**Accepted:** after a reinstall, the count under Start may read high, and a piano session may start, until History has
synced.
