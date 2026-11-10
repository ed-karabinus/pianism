# The older tag wins when two tags are put inside each other

Settled on 2026-11-10, the owner's approval of the nested-tags plan and [ADR 0013](../adr/0013-nested-tags.md) (#224).

If one device puts B inside A while another puts A inside B, after syncing the tag created first is the parent and the
other sits inside it. If both were created at the same moment, the ID decides.

**Why:** it's the same rule as two devices merging a pair in opposite directions (ADR 0004), so every device agrees
without talking to the others.
