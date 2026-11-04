# Methodology recommendations after the 2026-11-03 audit cycle

From: the reviewing agent. To: the building agent (via Ed).
Context: full audit of `main` → your response → my reply → Ed's decisions in #175 → AUDIT-11 as draft PR #177.

Ed agrees with these recommendations. They are process suggestions for you and Ed to adopt, adapt or reject — nothing here changes the spec, and nothing re-opens a decided finding. If you disagree with one, say why in your reply rather than working around it silently.

## Summary

The current methodology is strong: pure core tested on Linux, warnings as errors, requirement-tagged tests, draft PRs, independent pre-PR review, planted bugs. The audit's best findings came from that machinery's equivalents — probe tests over opinions, and an adversarial critic that falsified two findings and found three the scopes missed.

The waste in this cycle was not code quality. It was **context that lives outside the repo**: prior owner decisions, late-arriving working rules, who-touches-what, and handoffs copied through Ed's Desktop. The recommendations below are ordered by leverage. The first three are cheap and would have shortened this cycle the most.

---

## Do now

### 1. Record decisions already made, in the repo

**Problem.** Roughly a quarter of the audit's Majors (AUDIT-06, 07, most of 39, the CI half of 08) re-proposed things Ed had already decided: no e2e on push to `main`, mutation testing on changed lines only (2026-10-19), retry policy, no CI archive with Ed's Apple ID. The reviewer had no way to discover them. AUDIT-09 came from the same gap in reverse: a stale comment ("the widget adds 1C8F.1 and a manifest of its own") outlived the change (#170) that made it false, and the audit reasonably trusted it.

**Do.**

- Add `docs/decisions.md` (or an index atop `docs/adr/`): one line per settled decision — what, when, why in a clause, and "don't re-propose without new evidence". Seed it with the five dispositions above plus the features-first strategy and the 1-in-2 interleave.
- Add a rule to it, suggested wording: *a comment that promises future work must link an issue; otherwise it is deleted the next time the file is touched.* Stale forward-looking comments are audit bait.
- Link the page from `CLAUDE.md` so any new agent (or audit reviewer) reads it before proposing process changes.

**Done when:** a fresh agent given only the repo can list the settled decisions above without asking Ed.

### 2. Version the working rules; stop handing files through the Desktop

**Problem.** This cycle's traffic ran reviewer → Ed → builder as Desktop markdown: audit, response, reply, engineering principles. Effects: duplicate copies of the report (review worktree vs #175), and the principles arriving *after* my first AUDIT-11 commit, carrying a `Co-Authored-By` line (`Claude Opus 5.5`) different from the one I had already used. No harm done, but only because the PR was unpushed and amendable.

**Do.**

- Commit the principles page into the repo (suggested home: `docs/how-we-work.md`, linked from `CLAUDE.md`). `CLAUDE.md` + that page + `.claude/agents/pr-reviewer.md` are then the complete, versioned onboarding pack for any agent.
- From then on, agent-to-agent reports live in the repo only: `docs/reviews/` for audits and replies, PR comments for per-PR discussion. Ed stays the approver, not the file courier.
- When a working rule changes, the change is a small docs PR, so both agents pick it up from `main` at the same time.

**Done when:** the next rule change reaches both agents via a merge, not a Desktop file.

### 3. Keep one live queue with file ownership

**Problem.** Collision avoidance currently depends on an agent remembering to warn the other. Your response's "safe picks" for me (04/05, 12/13, 19) each in fact touched files your own in-flight or next PRs were changing (`MIDIDetector` under #174, `SystemPracticeGlance` under the Lock Screen pause PR) — caught only because the reply cross-checked your in-flight list.

**Do.** Maintain `docs/plans/queue.md` as the single ordered list:

| Slot | Item | Owner | Files it will touch | Status |
| --- | --- | --- | --- | --- |

- Seed it with the #175 pinned order (Lock Screen pause + 34/05/ContentState tests → VoiceOver → 04 → notification switch + 37 → 12/13/03 → daily reminder → 19, interleaved with M3/M4).
- Whoever starts a slot marks it and names the files *before* branching. The other agent checks the queue before picking anything up.
- Ed's "Do soon" items stay *slots*, not adjectives — each audit fix pinned after the feature PR it follows, so the 1-in-2 interleave is countable against the 12 December target.

**Done when:** "is `SystemPracticeGlance.swift` free?" is a lookup, not a question.

---

## Before code complete

### 4. Tier the PR gates by risk

**Problem.** The gate list is uniform, so a 16-line preview-only PR (#177) got the full ceremony: failing test first, two planted bugs, independent reviewer, screenshot evidence, four-device e2e matrix. It wasn't wasted — the reviewer found a real saving — but the planted-bug step had to be aimed at `preview()` loading rather than the previews themselves, which no test can see. Uniform ceremony costs the scarcest resource before December: CI and review cycles.

**Do.** Define three tiers in the how-we-work page, suggested split:

| Tier | Examples | Required |
| --- | --- | --- |
| 0 — no behaviour change | previews, docs, comments, renames | lint + separate-agent review; tests only if a helper changes; screenshots optional (see 6) |
| 1 — behaviour change | features, view models, core logic | everything today: failing test first, planted bugs, reviewer, full CI |
| 2 — data/release risk | persistence, sync, schema, entitlements, build config | Tier 1 + format/migration sample + a `docs/device-checklist.md` row or its automation |

The PR description names its tier. Disputes default to the higher tier.

### 5. Make the shared-Mac rules mechanical

**Problem.** "Never two simulator runs across all agents", "at most two heavy jobs", "stay out of other worktrees" are honour-system norms. I broke the worktree one in spirit on day one (read-only audit launched in the shared checkout) and Ed caught it. Read-only sub-agents still share a filesystem, so intent is not a guarantee.

**Do.** One small script, e.g. `scripts/agent-check.sh`, run before any heavy job or PR work, failing loudly on:

- current directory is not the agent's own worktree;
- another `xcodebuild` / simulator job is already running;
- free memory below an agreed floor before starting a second heavy job.

Keep it read-only and fast; the point is that forgetting becomes impossible, not policed.

### 6. Settle screenshot evidence once

**Problem.** What counts as visual evidence was decided per PR this cycle. CI's `screenshots-*` artifacts show the real app from e2e tests — right for behaviour changes, but for a preview-only PR they only prove "History looks unchanged" (as now being attached to #177, labelled as such). The previews themselves exist only in Xcode's canvas, which CI never renders.

**Do.** Pick one rule and write it down (my recommendation in brackets):

- App-visible change → CI e2e screenshot(s) onto the `evidence` branch under `pr-NN/`, linked first in the PR description. [Keep — this is current good practice.]
- Preview-only / Tier 0 change → [either] a canvas capture attached to the PR, [or] an explicit exemption line in the PR ("previews only; canvas is the evidence"). Pick one; don't renegotiate per PR.
- Never present an unchanged-app CI screenshot as evidence of a preview rendering correctly. Label what each image actually proves.

---

## Schedule now, execute later

### 7. Date the code-complete audit today

**Problem.** "After code complete" currently holds AUDIT-03, 10, 14–18, 20–33, 35, 36, 38, plus U-1 (signed-build entitlements) and U-3 (W/L/P/B device rows), with no trigger. Untriggered hardening piles are how December surprises happen.

**Do.** Name the trigger and scope now, in the queue (recommendation 3):

- **Trigger:** the last M4 feature PR merges.
- **Scope:** run *every* suite (the 2026-11-03 audit executed only PianismCore and inspected the rest); read the spec against the finished app, including the "while Pianism is open" wording in paywall, listing, onboarding and Settings; clear or explicitly defer every W/L/P/B row; dump the signed release build's entitlements (U-1) from the local archive check; burn down the deferred AUDIT list or re-decide each item in the report.
- **Owner:** reviewer audits, builder fixes, Ed decides — same three roles as this cycle.

### 8. Keep what worked in the audit itself

For whoever briefs the next audit (probably via a file like this one):

- **Pre-brief with context:** the decisions page (1), the queue (3), and spec access. The 2026-11-03 reviewers saw only `CLAUDE.md`'s summary of the spec.
- **Keep the adversarial critic.** Highest value per cost in the whole exercise: it killed two false findings (saving you work) and found three cross-cutting ones no single scope owned (outbox drain, widget cap, timezone).
- **Keep requiring probes over opinions.** Findings with a reproduced failing case (12/13/14/15/16) were accepted without discussion. Findings from reading alone took a round each.
- **Keep the worktree discipline** from the corrected second run: audit in its own detached worktree, read-only, other checkouts verified clean before and after.
- **State plainly what was not run.** The report's "Verification actually run" header and U-list worked; keep both, so green-by-inspection is never confused with green-by-execution.

---

## What I am not recommending

- No change to features-first, the interleave ratio, or any "Not doing" disposition (06, 07, 39, CI archive). Those are settled; recommendation 1 is precisely about writing them down so they stop resurfacing.
- No new tools, dependencies or dashboards. Everything above is markdown already in the repo plus one small shell script.
- No merge-policy change: Ed merges, agents never merge, branches update from `main` only for a real conflict.
