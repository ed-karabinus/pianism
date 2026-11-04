#!/bin/zsh
# Run before a heavy job on a shared Mac (a build, a test run, mutation testing). Fails if this isn't a
# worktree of its own, if another test or simulator run is going, or if free memory is low. Read-only.
fail() { print -u2 "agent-check: $1"; exit 1 }
top="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not in a git checkout"
[[ "$top" == "$HOME/Developer/Pianism" ]] && fail "this is the main checkout; work in a worktree of your own"
[[ "$PWD" == "$top"* ]] || fail "not inside $top"
pgrep -f "xcodebuild.*test" >/dev/null && fail "another xcodebuild test run is going; wait for it"
xcrun simctl list devices booted 2>/dev/null | grep -q Booted && fail "a simulator is booted; another run may be using it"
free=$(vm_stat | awk '/Pages free|Pages speculative/ {sum += $NF} END {print int(sum * 16384 / 1048576)}')
(( free >= ${AGENT_CHECK_MIN_FREE_MB:-1500} )) || fail "only ${free} MB free; wait for another job to finish"
print "agent-check: ok (${free} MB free)"
