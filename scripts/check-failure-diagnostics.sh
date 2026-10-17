#!/usr/bin/env bash
# Fails unless the deliberate failure in LaunchTests kept the screen and the app's UI tree, which
# UITestCase attaches to every UI test failure so that a failure on CI can be diagnosed from its results.
# Usage: scripts/check-failure-diagnostics.sh build/results/app-iPhone.xcresult
set -euo pipefail

names=$(xcrun xcresulttool get test-results activities --path "$1" \
  --test-id "LaunchTests/testAFailureKeepsTheScreenAndUITree()" | jq -r '.. | objects | .attachments[]?.name')
for kept in "Screen at failure" "UI tree at failure"; do
  if ! grep -q "^$kept" <<<"$names"; then
    echo "A failing UI test no longer keeps its \"$kept\": see UITestCase in AppUITests/LaunchTests.swift." >&2
    exit 1
  fi
done
