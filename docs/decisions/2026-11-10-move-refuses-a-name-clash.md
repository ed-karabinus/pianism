# Move refuses to put two tags of one name in the same list

Settled on 2026-11-09 (Q1, the nested-tags plan, #224).

A move that would put a piece or skill in a list that already has its name, case and accents aside, doesn't happen.
An alert says why: "A skill named “D minor” is already at the top level. Rename one first." or "A skill named
“D minor” is already inside “Arpeggios”. Rename one first." The Move screen stays open.

A move inside a piece or skill of its own name, case and accents aside, is refused the same way: "A skill can't sit
inside one with the same name. Rename one first." (the owner's pick 2026-11-10, as Add Inside and Rename refuse it).

**Why:** names are unique within each list, so a move can't break that either way. Two devices moving one name out at
once can still make two top-level tags of that name, which can then be merged. A tag named like the one it's inside
reads like a mistake.
