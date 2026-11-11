# A tag synced two levels deep shows at the top level

Settled on 2026-11-10, the owner's approval of the nested-tags plan and [ADR 0013](../adr/0013-nested-tags.md) (#224).

Tags nest one level deep. If two devices offline put C inside P and D inside C, then after syncing C shows inside P
and D shows at the top level. Moving C out to the top level puts D back inside C, with nothing written to D. Three
devices nesting in a ring (T inside P, P inside G, G inside T) show all three at the top level.

**Why:** every device reads the same thing from the same records, with no device "fixing" another's data, and the
link each person set is kept, so a Move can bring it back.
