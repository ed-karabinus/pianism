<!-- Title: "<Requirement ID>: <what changes>", e.g. "SES-3: Ask 'Still practicing?' after 90 minutes" -->

## Problem

<!-- What is wrong or missing, for the user or the codebase. Cite the requirement ID or spec section. -->

## Fix

<!-- What this PR changes and why this approach; alternatives rejected, briefly. -->

**Where to start reading:**

1. <!-- the file that explains the change best -->

**Size:** <!-- production lines: estimated N (and where: plan, issue or earlier PR), actual M. Over 1.5×: why. -->

## Testing

<!-- Evidence, not claims. -->

- **Automated:** <!-- tests added or changed, by name, plus the summary line of `make test` -->
- **Visual:** <!-- screenshots or a recording for any UI change (before and after when something changed). `make evidence` exports the screenshots the UI tests captured. Otherwise: "No UI change." -->
- **Manual:** <!-- anything checked by hand or on a device, each with the automated test that now covers it or its follow-up issue (CLAUDE.md, Workflow 8); or "None needed." -->
- **Independent review:** <!-- what the review agent (.claude/agents/pr-reviewer.md) found: each finding applied (lines saved) or rejected (why). Apple sample code compared, if a framework is new. -->

## Issue

<!-- "Closes #N". Requirement IDs covered. Anything deferred, with its follow-up issue. -->

---

### Definition of done

- [ ] Each acceptance criterion maps to a named test (or a device-checklist item)
- [ ] Each manual check above has an automated test or a follow-up issue
- [ ] A separate agent reviewed the branch; every finding is applied or answered above
- [ ] `make lint test` passes locally; zero warnings
- [ ] UI changes have screenshots above; new views have previews in light, dark and AX5
- [ ] New controls have VoiceOver labels; new strings are in the String Catalog
- [ ] No new third-party dependency (or an approved ADR is linked)
- [ ] No test was weakened, skipped or deleted (or it's explained above)
