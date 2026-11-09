# CI skips the Mac jobs on a commit that already passed

Settled on 2026-11-08, the owner's pick.

A pull request's CI run skips Periphery, the adapter tests and the end-to-end tests when another pull request run
already passed on the same head commit; the required summary accepts that run. Core and Format always run.
Re-testing a commit that passed takes a new commit.

**Why:** a run cancelled by a duplicate on the same commit leaves required checks cancelled until it's re-run, and the
re-run then took an hour (#208). A skip only ever follows a full pass on that exact commit. The duplicate came from a
redundant base edit after a push, which agents no longer make.
