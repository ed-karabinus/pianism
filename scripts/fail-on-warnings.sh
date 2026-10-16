#!/bin/bash
# Runs a build or test command, then fails if the compiler printed any warning (#24).
#
# Every target already treats warnings as errors, but Swift reports some Sendable problems at calls
# into @preconcurrency APIs, such as DispatchQueue.concurrentPerform, as warnings that the setting
# doesn't upgrade. Only compiler diagnostics (path:line:column: warning:) count: Xcode's own tools
# print warnings such as "not stripping binary because it is signed" that aren't ours to fix.
# Only code this run compiles can warn, so a cached local build may pass; CI builds from scratch.
set -uo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

"$@" 2>&1 | tee "$log"
status=$?

# Swift colours its diagnostics even when piped, so strip the colour codes before matching.
esc=$'\033'
if warnings=$(sed "s/${esc}\[[0-9;]*m//g" "$log" | grep -E '^[^ ]+:[0-9]+:[0-9]+: warning: ' | sort -u); then
    echo "error: the compiler warned. Fix each warning:" >&2
    echo "$warnings" >&2
    exit 1
fi
exit "$status"
