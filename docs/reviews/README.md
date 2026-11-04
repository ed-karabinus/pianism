# Reviews

Independent quality reviews of Pianism, written so another coding agent can act on them without re-doing the investigation.

## How to use a report

1. Read the report's **Decisions** section first: what the owner decided to do, defer or not do, and why. Work the "Do" items; the report's own fix order is the reviewer's suggestion.
2. One finding (or one tight cluster) per branch/PR, per `CLAUDE.md`. Name the branch after the finding ID, e.g. `audit-03-negative-cap-guard`.
3. For every bug finding: first add a test that fails on current `main`, then fix, then keep the test. Follow the report's **Test to add** line.
4. Run `make lint unused build test` before pushing (use the narrower `make test-core` / `test-features` / `test-adapters` while iterating, as the finding says).
5. If you dispute a finding, reply in the PR with the file/line evidence that falsifies it — do not silently skip it. Two findings in the first report were already disputed and dropped by the review's own critic; see **Disputed and dropped** in that report.
6. When a finding is fixed, tick it in the report's checklist in the same PR.

## Reports

| Report | Scope | Base |
| --- | --- | --- |
| [Full audit of main (2026-11-03)](2026-11-03-full-audit-main.md) | All packages: core, features/UI, persistence/CloudKit, MIDI/widgets, tests/CI/App Store | `main` at `fea4df4` |
