# An archived parent with something live inside it shows again

Settled on 2026-11-10, the owner's approval of the nested-tags plan and [ADR 0013](../adr/0013-nested-tags.md) (#224).

If one device archives a piece or skill while another adds something inside it, after syncing the parent shows as
unarchived, with the new tag inside. Nothing is written: once everything inside it is archived, it shows as archived
again, as it was stored.

**Why:** an archived tag then never has anything live inside it, which is what blocking the archive on one device
(D1) promises, so no screen needs an "archived parent" state.
