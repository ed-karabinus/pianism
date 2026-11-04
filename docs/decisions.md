# Settled decisions

Decisions the owner has made that last beyond one PR. Read this before proposing a process, tooling or scope change; don't propose one of these again without new evidence. When the owner settles something lasting, add a line in the same PR. Per-requirement product decisions live in the spec and its issues; architecture lives in `docs/adr/`.

| Date | Decision | Why |
| --- | --- | --- |
| 2026-10-15 | The owner merges every PR; agents never merge. | He reviews what ships. |
| 2026-10-15 | CI never uses the owner's Apple ID. Uploads, App Store Connect and submission are his actions; no CI archive or upload job. | Signing credentials stay with him. |
| 2026-10-17 | No subscription in v1. Pro is a one-time purchase; MIDI auto-start is Pro, with the first 5 auto-logged sessions free. | A monthly charge through months without practice goes against the no-guilt promise. |
| 2026-10-19 | Mutation testing runs for PRs that add logic, and only survivors on changed lines need action. The unused-code check is left to CI. | Local check time is spent where it finds bugs. |
| 2026-10-21 | Branch protection doesn't require branches to be up to date. Update a branch with `main` only for a real conflict. | Each update reruns the full CI. |
| 2026-10-21 | No end-to-end run on pushes to `main`; the nightly run covers it. | Runner time; PRs already run the full matrix. |
| 2026-10-24 | "Still practicing?" and the cap don't apply to MIDI sessions: a silence pauses and ends them. | They can't be forgotten (#43). |
| 2026-10-31 | UI tests retry once on failure, and a test past 15 minutes fails (#156). | Simulator flakes (#136) cost more than the retries hide. |
| 2026-11-02 | Settings live in the app's own UserDefaults; the widget reads no settings, and the cap reaches it in the totals file (ADR 0010, spec amended). | The widget needs no App Group defaults or required-reason API. |
| 2026-11-02 | No local iOS 26 simulator; install it only to root-cause an iOS 26-only failure. | Almost every failure is iOS 27-specific or common to both. |
| 2026-11-03 | Features first until code complete, aiming at App Review by 12 December. Audit fixes go in as slots, about one per two feature PRs. | The date. |
| 2026-11-03 | The work queue is pinned issue #179: owner and files per slot, checked before branching. Not a repo file. | A file would cost a full CI run per edit. |
| 2026-11-03 | Pianism hears a piano only while it's open on screen, and everything that promises auto-logging says so. Outside the app, a MIDI session shows paused at its last note (#178). | iOS suspends the app; no background mode allows MIDI. No overselling. |
| 2026-11-03 | EU trader status waits (non-EU sales first); TestFlight testers wait until code complete. | Owner's call. |
| 2026-11-03 | A comment that promises future work links an issue, or it's deleted the next time its file is touched. | A stale promise misled the audit (finding 9). |
| 2026-11-03 | The code-complete audit runs when the last M4 feature PR merges: every suite run, the spec read against the finished app (the "while Pianism is open" wording included), every device-checklist row cleared or deferred by the owner, the signed release build's entitlements checked (audit U-1), and every deferred audit finding done or decided again. The reviewing agent audits, the building agent fixes, the owner decides. | Hardening needs a trigger, or it piles up. |
| 2026-11-03 | Agents hand each other reports through the repo (`docs/reviews/`, PR and issue comments), not files passed by the owner. A change to the working rules is a docs PR. | Both agents pick it up from `main` together. |
