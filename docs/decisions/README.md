# Settled decisions

Decisions the owner has made that last beyond one PR, written down so agents stop proposing them again by accident.
Read these before proposing a process, tooling or scope change. To change one, say what's new and ask the owner;
nothing here is frozen. **Settled** means the owner decided it as a rule; **For now** means it's how things are, and
it's open to a better idea. Per-requirement product decisions live in the spec and its issues; architecture lives in
`docs/adr/`.

Decisions recorded before this folder started (2026-11-09) are in the table in [`../decisions.md`](../decisions.md).
Each one since is a file here.

## Adding one

When the owner settles something lasting, add a file in the same PR, so two PRs never edit the same lines (a shared
table made every merge conflict with every open PR, and each fix cost a full CI run). Name it for the day it was
settled and what it's about, `YYYY-MM-DD-short-name.md`, so the folder reads in date order:

```markdown
# Docs-only pull requests skip the Mac jobs

Settled on 2026-11-08, the owner's pick.

A pull request that changes only Markdown at the top level, in docs/ or in .claude/ skips Periphery, the adapter
tests and the end-to-end tests.

**Why:** nothing built or tested reads those files, and a docs change was holding the macOS runners for hours.
```

Where it's "For now", the line reads "For now since 2026-11-08, the owner's pick." To change a decision, edit its
file, or its row in the table, and say so there with the date: the history stays in git.
