# Handover tools

Scripts the agent sessions use day to day. They are not part of the build; `make` never runs them.

| Script | What it does |
| --- | --- |
| `e2e-class.sh <name> <PracticeTests method>…` | Builds for testing and runs only the named UI tests on the iPhone simulator, as `make test-app` would; result bundle at `build/results/e2e-<name>.xcresult`. `WT=<checkout>` picks another worktree, `DEVICE=iPad` the iPad. |
| `e2e-record.sh <name> <test>` | The same for one test, recording the simulator's screen to `VIDEO=<file>.mp4`. A recording sometimes comes out black; run it again. |
| `plant-swift.py <worktree> <package dir> <test filter> <source file>` | Plants bugs one at a time (JSON `[[name, old, new], …]` on stdin), running the filtered `swift test` clean first and after each plant, restoring the file each time. The planted-bug table in a PR comes from this. |
| `flake-analyze.py <job logs>…` | Per end-to-end CI job: runner image, iOS runtime, each test iteration's time, and counts of the known flakes (#136). Feed it `gh run view --job <id> --log` output. |

The video helpers that trim a recording and dump its frames stay out: they are one-off scripts that don't meet the repository's lint rules, and `e2e-record.sh` is what makes the recording.

`docs/plans/` holds the implementation plans the agents work from, one per feature, as written before the work started.
