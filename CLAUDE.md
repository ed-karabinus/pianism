# Pianism — agent instructions

Pianism is an iOS piano practice tracker. It is a product and a showcase of engineering craft:
hold every change to the standard a staff-level reviewer would expect.

**Source of truth:** the [business plan & product spec](https://claude.ai/code/artifact/40798124-1441-4f6f-a057-b3c6542e5da7).
It defines requirement IDs (`SES-1`, `MIDI-R3`, `NFR-4`…), product principles `P1`–`P8`,
engineering principles `E1`–`E8`, and the definition of done. Never edit the spec; propose changes
to the owner.

**Before proposing a process or scope change,** read what's settled, and why: the files in `docs/decisions/` and
the older table in `docs/decisions.md`. A decision the owner settles in a PR gets its own file in `docs/decisions/`
(see `docs/decisions/README.md`).
**Before branching,** check the pinned work queue (issue #179) for what's next.

## Commands

| Command | What it does |
| --- | --- |
| `make test-core` | Unit tests for `PianismCore` (seconds, no simulator) |
| `make test-features` | Unit tests for the view models in `PianismFeatures`, on macOS (seconds, no simulator) |
| `make test-adapters` | Integration tests for the adapter packages, on macOS against real files (seconds, no simulator) |
| `make test-app` | Builds the app and runs end-to-end tests on iPhone and iPad simulators (`DEVICES=iPhone` for one) |
| `make test` | All of the above |
| `make lint` / `make format` | Check / apply swift-format |
| `make unused` | Fails on unused code in the app and the package code it builds (Periphery, pinned by checksum). Keep an intentional exception with `// periphery:ignore - <reason>` |
| `make mutate` | Mutation testing of the core and adapters (minutes). Run it for PRs that add logic there; a survivor on a line the PR changed gets a test, a deletion or `// mutate:ignore - <reason>` (owner, 2026-10-19). CI also runs all of it nightly on main; a survivor fails that job, which isn't a required check, so it blocks no merge (owner, 2026-11-06) |
| `make build` | Release build for the simulator, as the app ships; the tests build Debug |
| `scripts/agent-check.sh` | Run before a heavy job (build, test run, mutation): fails if you're not in your own worktree, another simulator run is going, or memory is low |
| `make evidence` | Exports the screenshots the last `test-app` run captured, for the PR's Testing section |

Run `make lint unused build test` before every push. CI runs the same commands.

## Layout

- `App/`, `AppUITests/` — the app and its end-to-end tests. These are synchronized folders:
  **add files on disk; never edit `project.pbxproj` to add a file.**
- `Packages/PianismCore` — pure Swift rules. No SwiftUI, SwiftData, CoreMIDI, StoreKit or UIKit
  imports (CI tests it on Linux, so it will fail). Shared test doubles go in `PianismCoreTestSupport`.
- `Packages/PianismFeatures` — SwiftUI screens and view models.
- `Packages/PianismPersistence` — storage adapters, such as the running-session file (ADR 0003).
  Tested on macOS with `make test-adapters`.
- `Packages/PianismSystem` (notifications) and `Packages/PianismMIDI` (CoreMIDI) — more adapters, also
  tested by `make test-adapters`.
- More adapter packages (Purchases) arrive as needed; each implements a port defined in the core, unless
  only the app calls it, as with `PianismMIDI`. Add each new one to `ADAPTERS` in the `Makefile`.
- `Config/*.xcconfig` — all build settings. Change settings there, not in the project file.
- `docs/adr/` — architecture decision records.

## Rules

- Never read the system clock directly: take a `WallClock` (E3). Tests use `ManualClock`.
- No sleeps or real time in tests; no real network or hardware below the device layer (E4).
- No third-party dependencies without an ADR approved by the owner (E5).
- Swift 6 language mode, warnings are errors, no force unwraps or `try!`. `make` and CI also fail on the
  few compiler warnings that setting misses, such as Sendable captures at `@preconcurrency` APIs (#24).
- Data on a device must still read after an update. A new field on `PracticeSession`, which is stored
  as JSON, is optional or decoded with `decodeIfPresent`, and a format change adds a sample to
  `SessionFileFormatTests` (ADR 0003). The synced schema follows ADR 0006.
- Every user-facing string goes through the String Catalog; every control gets a VoiceOver label.
- New views get `#Preview`s in light, dark and AX5 text size.
- Never promise more than the app does. Pianism hears a piano only while it's open on screen (iOS
  suspends it otherwise, and no background mode allows MIDI), so the paywall, App Store text,
  onboarding and Settings say "while Pianism is open".
- Tests use Swift Testing (`import Testing`) except UI tests, which use XCTest and subclass
  `UITestCase`, so a failure keeps its screen and UI tree. Name each test after the behaviour it
  proves and tag it with its requirement ID.

## Keeping the code small

Agents write code quickly, so the main risk is code that works but shouldn't exist.

- No protocol with a single implementation, unless it's a port the core defines or a seam tests need.
- Nothing without a caller today: no parameters, options, enum cases or public API "for later".
- Use the platform before writing your own: `@Bindable` rather than a hand-built `Binding`, a
  Foundation formatter rather than string arithmetic. When a framework is new to the codebase, read
  Apple's sample code for it first, and say in the PR which sample you compared and where we differ.
- Comments say why, not what. Document public API; comment private code only when the why isn't
  obvious.
- Prefer deleting to adding. A PR that only removes code is always welcome.

## Workflow

1. Work on a branch named after the ticket, for example `ses-3-still-practicing-nudge`.
   Never push to `main`.
2. One ticket per pull request, under about 500 lines of production code (tests, docs and
   generated files don't count). It's a guideline, not a hard limit: split along sensible seams,
   and if a change is genuinely indivisible, say why in the PR. Squash merges make the PR title
   main's commit, so titles and commit messages follow Conventional Commits with the requirement ID
   as the scope: `feat(SYN-1): Store a session's tag IDs as JSON`. Work on a requirement is `feat`,
   or `fix` for a bug in shipped behaviour; other work is `build`, `chore`, `ci`, `docs`, `perf`,
   `refactor` or `test`, scoped by a requirement when it's about one: `docs(MIDI-1): Record the
   device checks`. The summary starts with a capital, and CI checks the title
   (`.github/workflows/pr-title.yml`). The description says what, why, how it was tested, and where
   to start reading. The owner reviews and merges every PR; agents never merge.
3. Anything that adds a module, a dependency or a persistent model change needs a short plan (and an
   ADR if it changes the architecture) approved by the owner before you write code.
4. Estimate the production lines before you start, and report the estimate and the actual in the
   PR. More than 1.5 times the estimate needs a sentence explaining why.
5. Every PR is reviewed by agents that didn't write it (#180). A review stays on the PR: it isn't a
   re-audit, and it doesn't propose again anything settled in `docs/decisions/` or `docs/decisions.md`
   without something new. The author applies each finding or says why not in the PR's Review section, which ends with
   a count: findings, applied, not applied. A disagreement goes to the owner, not back and forth.
   - **The reviewing agent** (Muse, which reviews and doesn't build: owner, 2026-11-05): once the
     draft's code is final, ask with a note in the local mailbox (`~/Developer/pianism-mail/`, see
     its README). The review is one PR comment headed "Review by the reviewing agent", with findings
     numbered most serious first, each with file, line and what goes wrong, or what was checked and
     found fine. It's read and probed from the reviewer's own worktree, with no bugs planted by the
     reviewer. It never blocks: the PR goes ready on green CI without it, and a late finding that's
     real is fixed before the merge. If it has no capacity left, the PR says the review didn't
     happen. The Review section also counts its findings that changed code or added a test and that
     no other review had caught, which is how the owner judges whether to keep it.
   - **A fresh review agent** with the brief in `.claude/agents/pr-reviewer.md`, for Tier 1 and 2,
     kept from the other reviews so it reads the change on its own.
6. Never weaken, skip or delete a test to make it pass without saying so in the PR.
7. Report results faithfully: if something failed or was skipped, say so.
8. Every check made by hand, in a PR's Manual section or while trying a build on a device, gets an
   automated test in that PR or a follow-up issue that says how it will be automated. If it can't
   be automated, the issue says why and the check becomes an entry in `docs/device-checklist.md`
   (start the file with its first entry). When the owner reports a problem from using the app,
   write a test that fails on it before fixing it. The same goes for any bug: the failing test first.
   An issue with rows left in that file stays open until they pass: its last PR says "Part of", not
   "Closes", and the agent closes the issue with a short comment when the last row passes. A row that
   needs hardware the owner doesn't have says so and doesn't hold the issue open. With no rows left,
   the last PR says "Closes".
9. Before calling a change done, plant bugs in the new logic (two to five, each a likely mistake) and
   show the tests catch each one; the PR lists them. A plant no test catches means a missing test.
   The PR names its tier, and the higher one wins a doubt:
   - **Tier 0, no behaviour change** (previews, docs, comments, renames): the reviewing agent's review and
     CI only; no
     failing test or planted bugs unless a helper changes, and "No visible change" or "Previews only"
     in place of a screenshot.
   - **Tier 1, behaviour change** (features, view models, core logic): everything in this list.
   - **Tier 2, data or release risk** (storage, sync, schema, entitlements, build settings): Tier 1,
     plus a format sample for a stored change and a device-checklist row or its automation.
10. Open each PR as a draft once the code is final, so CI runs while you finish. Mark it ready only
    when every CI job is green, then tell the owner. Update a branch with `main` only for a real
    conflict, as each update reruns CI.
11. In the description, lead with what the owner will see change (layout, wording, a test changed),
    with a screenshot (the `evidence` branch, under `pr-NN/`). Label what each image proves; an
    unchanged screen is never evidence that a preview renders. A PR holds no open questions: settle
    wording and behaviour with the owner first, and the PR states the decision.
12. Commits end with a `Co-Authored-By:` line naming the agent that wrote them, and PR descriptions
    with "Generated with <the agent that wrote it>". No session links in either.
13. Go easy on GitHub: the bot account was flagged once for a burst of writes. Poll CI every five
    minutes at most, cancel a run a newer push replaced, and open issues a few at a time.

## Working with the owner

- Write in plain, casual, precise language with little jargon. Leave out hashes and run IDs unless
  they're needed.
- Ask about any default, behaviour, wording or scope you're unsure of, batched, with your
  recommendation first. Give your real view, and disagree when the evidence says so.
- Approval is the owner writing "I approve <X>". A bare "ok" isn't approval.
- A change to the spec needs the owner's authorization for those exact lines, and each
  authorization is used once.
- Secrets (tokens, passwords) are entered only in the owner's own Terminal, never through chat or a
  command an agent runs. Never publish the owner's email address; commits use the no-reply one.
