# A pull request runs two device pairs, each in halves

Settled on 2026-11-12, the owner's picks.

A pull request's end-to-end tests run on two of the four device and iOS pairs, crosswise, picked by its number: an
even one runs an iPhone on iOS 27 and an iPad on iOS 26, an odd one an iPhone on iOS 26 and an iPad on iOS 27. Each
pair runs as two jobs, each taking half the tests (`scripts/ui-test-half.sh`). So a pull request still has four
end-to-end jobs, and 11 checks. The nightly and manual runs still take all four pairs whole, plus the iPhone on 27.0.

**Why:** each pull request's four whole jobs took 60 to 96 minutes and held four of GitHub Free's five macOS slots, so
a second pull request's run queued behind the first. Crosswise, each pull request still covers both devices and both
iOS versions, and alternating covers all four pairs across any two pull requests. A pair a pull request skips is tested
by that night's run at the latest.

This changes the reason given in the 2026-10-21 row of [`../decisions.md`](../decisions.md), "PRs already run the full
matrix": they no longer do, but the nightly run still does, so pushes to `main` still skip the end-to-end tests.
