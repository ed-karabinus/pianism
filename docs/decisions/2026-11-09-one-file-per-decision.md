# One file per decision

Settled on 2026-11-09, the owner's pick.

Each decision is its own file in `docs/decisions/`, named `YYYY-MM-DD-short-name.md`, in place of a row at the end of
the table in `docs/decisions.md`, which keeps the decisions merged before 2026-11-09.

**Why:** almost every pull request added a row at the table's end, so each merge put every other open pull request in
conflict over that one file, and each fix was a new commit with a full CI run, about four hours of the 5 shared macOS
runners (#211, #214, #216 and #217 on 2026-11-09). Separate files never touch the same lines. The owner relies on
these to remember decisions, so they stay one place to read, in date order.
