# Moving a tag out of a mutual nesting clears the other tag's link too

Settled on 2026-11-10, the owner's approval of the nested-tags plan and [ADR 0013](../adr/0013-nested-tags.md) (#224),
for the parent a tag leaves, and the owner's pick of 2026-11-10 for the parent a tag joins.

When two devices put A and B inside each other, the older one shows as the parent, and the other still names the
newer one as its parent, unseen. Moving the newer one anywhere clears that link too, so the older one stays where it
was instead of jumping inside it. The same goes for a tag moved inside one whose unseen link names it: that link is
cleared too. The plan and the ADR name only the parent a tag leaves; the owner settled the second case on
2026-11-10. The link is cleared before the tag itself moves, so if the second write fails, nothing has moved.

Move offers a tag to go inside only if that tag reads at the top level and stores no parent of its own, as Add Inside
requires, unless its link names the tag being moved, or it's where the tag already is (shown, never written). A
grandchild, a tag in a ring, the winner of a mutual nesting and a tag whose parent hasn't synced yet read top-level but
still name a parent, so a tag moved inside one would read top-level, now or once that parent arrives; they aren't
offered.

**Why:** a person moving one tag expects nothing else to move. A tag moved inside one whose link names it would leave
the two naming each other, and if the moved tag is the older, it wins, and its new parent lands inside it instead.
Clearing the link costs a second write to one tag, and sessions are never touched.
