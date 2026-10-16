# Pianism — agent instructions

Pianism is an iOS piano practice tracker. It is a product and a showcase of engineering craft:
hold every change to the standard a staff-level reviewer would expect.

**Source of truth:** the [business plan & product spec](https://claude.ai/code/artifact/40798124-1441-4f6f-a057-b3c6542e5da7).
It defines requirement IDs (`SES-1`, `MIDI-R3`, `NFR-4`…), product principles `P1`–`P8`,
engineering principles `E1`–`E8`, and the definition of done. Never edit the spec; propose changes
to the owner.

## Commands

| Command | What it does |
| --- | --- |
| `make test-core` | Unit tests for `PianismCore` (seconds, no simulator) |
| `make test-adapters` | Integration tests for the adapter packages, on macOS against real files (seconds, no simulator) |
| `make test-app` | Builds the app and runs end-to-end tests on iPhone and iPad simulators (`DEVICES=iPhone` for one) |
| `make test` | All of the above |
| `make lint` / `make format` | Check / apply swift-format |
| `make unused` | Fails on unused code in the app and the package code it builds (Periphery, pinned by checksum). Keep an intentional exception with `// periphery:ignore - <reason>` |
| `make mutate` | Mutation testing of the core and adapters (minutes). Run before milestone checks and for PRs that add logic there; each survivor gets a test, a deletion or `// mutate:ignore - <reason>` |
| `make build` | Release build for the simulator, as the app ships; the tests build Debug |
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
- More adapter packages (MIDI, Purchases, System) arrive as needed; each implements a port defined in
  the core. Add each new one to `ADAPTERS` in the `Makefile`.
- `Config/*.xcconfig` — all build settings. Change settings there, not in the project file.
- `docs/adr/` — architecture decision records.

## Rules

- Never read the system clock directly: take a `WallClock` (E3). Tests use `ManualClock`.
- No sleeps or real time in tests; no real network or hardware below the device layer (E4).
- No third-party dependencies without an ADR approved by the owner (E5).
- Swift 6 language mode, warnings are errors, no force unwraps or `try!`. `make` and CI also fail on the
  few compiler warnings that setting misses, such as Sendable captures at `@preconcurrency` APIs (#24).
- Every user-facing string goes through the String Catalog; every control gets a VoiceOver label.
- New views get `#Preview`s in light, dark and AX5 text size.
- Tests use Swift Testing (`import Testing`) except UI tests, which use XCTest. Name each test after
  the behaviour it proves and tag it with its requirement ID.

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
   and if a change is genuinely indivisible, say why in the PR. The PR title starts with the
   requirement ID; the description says what, why, how it was tested, and where to start reading.
   The owner reviews and merges every PR; agents never merge.
3. Anything that adds a module, a dependency or a persistent model change needs a short plan (and an
   ADR if it changes the architecture) approved by the owner before you write code.
4. Estimate the production lines before you start, and report the estimate and the actual in the
   PR. More than 1.5 times the estimate needs a sentence explaining why.
5. Before opening a PR that changes code, have a separate agent review the branch with the brief in
   `.claude/agents/pr-reviewer.md`. It must not be the agent that wrote the change. Apply each
   finding or say why not; the PR lists what the review cut and what it rejected.
6. Never weaken, skip or delete a test to make it pass without saying so in the PR.
7. Report results faithfully: if something failed or was skipped, say so.
