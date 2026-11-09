# Docs-only pull requests skip the Mac jobs

Settled on 2026-11-08, the owner's pick.

A pull request that changes only Markdown at the top level, in docs/ or in .claude/ skips Periphery, the adapter
tests and the end-to-end tests. Markdown anywhere else, such as in App/, which Xcode copies into the app, runs in
full, and so does any error working out what changed.

**Why:** nothing built or tested reads those files, and docs-only pull requests were holding the 5 shared macOS
runners for hours.
