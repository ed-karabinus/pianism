# 5. Unused code found by Periphery 3.8.0, and mutation testing by a script in the repository

- Status: accepted
- Date: 2026-10-15
- Pull request: the review discussion after #27, and #33

## Context and problem statement

Agents write code quickly, so the main risk is code that works but shouldn't exist. Review is the
first defence (#33), but a reviewer's judgment varies. Two automated checks don't depend on it:

- **Unused code:** declarations, parameters and `public` modifiers that nothing uses.
- **Mutation testing:** break one line at a time and run the tests. A break that no test notices
  marks a line that is either untested or unnecessary. It's the automated form of the planted bugs
  every PR already lists.

Both need third-party tools or our own code, and E5 requires an ADR for any third-party dependency,
including developer tools that never ship in the app.

The state of the tools in October 2026:

- **Periphery,** the standard Swift unused-code finder, became a commercial product in August 2026.
  Its open-source repository is archived, and 3.8.0 (July 2026, MIT licence) is the last
  open-source release. The commercial version is free for open-source and indie projects during an
  open beta that has no end date and no published prices.
- **Muter,** the only maintained Swift mutation tester, last released a version (v16) in
  September 2023. Its Swift Testing support exists only on its main branch. An issue filed on
  2026-10-11 (muter#321) reports that with Swift 6.3, a Swift package and Swift Testing, which is
  our setup, it plants no mutations at all and reports a fake score. A second issue (muter#322)
  reports that mutations inside closures, loop bodies and `if let` blocks are never applied.

## Considered options

For unused code:

1. **Periphery 3.8.0,** downloaded at a pinned version and checked against its SHA-256.
2. **Periphery's commercial version.**
3. **Compiler warnings only.** They catch unused local variables and results, but not unused
   declarations, parameters or `public`.

For mutation testing:

4. **Muter,** v16 or its main branch.
5. **A short script in the repository** that applies a fixed list of mutations.
6. **None,** relying on planted bugs by hand.

## Decision

Options 1 and 5.

**Periphery 3.8.0.** A trial on the Practice screen branch worked with Xcode 27 and Swift 6.4. The
whole scan took 31 seconds and reported 15 findings:

- 12 `public` declarations nothing outside their package uses, such as `PracticeView` and the
  accessibility identifiers.
- 3 unused `session` parameters, all in the stand-ins for session history that HIS-1 replaces.

How it runs:

- `make unused` downloads the pinned release into `build/`, checks its SHA-256, and scans the app
  scheme with `--strict`, which fails on any finding. The settings live in `.periphery.yml`.
- A finding that is intentional is kept with `// periphery:ignore - <reason>` on the declaration.
  The reason is required.
- CI gets a job, "Unused code (Periphery)", on macOS. It becomes a required check once it has run
  cleanly for a week of PRs.

**A mutation script, `scripts/mutate.py`.** It uses Python's standard library only, so it adds no
dependency.

- It mutates the sources of the packages that have their own tests, `PianismCore` and
  `PianismPersistence`. The app and features layers are covered by end-to-end tests, which are too
  slow to run once per mutation.
- Mutations: flip a comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`), swap `&&` and `||`, swap `+` and
  `-`, swap `true` and `false`, and delete a one-line statement.
- Each mutation is built and tested on its own. A failing test means the mutation was caught, and
  passing tests mean it survived. A mutation that doesn't compile is left out of the score.
- `make mutate` runs it. It runs before every milestone check, and by hand for a PR that adds
  logic to those packages. It isn't a CI check: it takes minutes, and some survivors need a person
  to judge them.
- Every survivor gets one of three outcomes, recorded in the milestone report: a new test, a
  deleted line, or a note that the mutation doesn't change behaviour.

A prototype ran on the Practice screen branch in 3 minutes. Of 44 mutations, 15 didn't compile,
and the tests caught 27 of the other 29. Both survivors were worth knowing about:

- `current()` taking a write claim instead of a read claim. That is still correct, only slower, so
  no test can notice. It is a mutation that doesn't change behaviour.
- Deleting `encoder.outputFormatting = .sortedKeys` in the running-session store. Nothing depends
  on the keys being sorted, so the line can go.

Option 2 is rejected for now. Its terms are unknown, and the repository may not stay public. It
remains the fallback if 3.8.0 stops working with a new Xcode. Option 3 misses everything the trial
found. Option 4 is rejected because of muter#321: its score would look like proof and mean nothing.
Muter will be evaluated again once a release fixes muter#321 and muter#322. Option 6 depends on
someone thinking of the right bug, which is what the planted-bugs tables already show is fallible:
the race test missed its first planted bug in #27.

## Consequences

- Good: two checks that don't depend on any agent's judgment. One finds code nothing uses, the
  other finds code no test needs.
- Good: no new dependency in the app. Periphery runs only in `make` and CI, and the script uses
  Python's standard library.
- Bad: Periphery 3.8.0 gets no more updates. A future Xcode may break it, and then we choose
  between its commercial version and dropping the check, in a new ADR.
- Bad: the script works on text, not on Swift's syntax tree, so it can't mutate everything. It
  never touches a statement split across lines, for example. It is a floor, not a full mutation
  tester.
- Bad: some surviving mutations don't change behaviour, and deciding which ones takes a person.
  That's why the script reports to the milestone check rather than failing CI.
