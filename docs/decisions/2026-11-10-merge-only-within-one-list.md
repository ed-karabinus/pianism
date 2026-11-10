# Only pieces or skills in the same list can be merged

Settled on 2026-11-09 (D2, the nested-tags plan, #224).

Merge offers only tags of the same kind in the same list: two tags inside one parent, or two at the top level. A tag
with anything inside it, archived or not, can't be merged, and isn't offered to merge into.

**Why:** a merged tag counts toward the one it was merged into, so a merge across parents, or of a parent, would leave
sessions counting toward a parent they don't show inside.
