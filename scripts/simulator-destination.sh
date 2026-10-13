#!/usr/bin/env bash
# Prints an xcodebuild -destination for an available iPhone simulator on the newest iOS runtime.
# Used by the Makefile and CI so neither hard-codes a device name that may not exist.
set -euo pipefail

udid=$(xcrun simctl list devices available --json | jq -r '
  [.devices | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-"))
    | {runtime: (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)), device: .value[]}
    | select(.device.name | startswith("iPhone"))]
  | sort_by(.runtime) | last | .device.udid // empty')

if [[ -z "$udid" ]]; then
  echo "No available iPhone simulator found. Install one with: xcodebuild -downloadPlatform iOS" >&2
  exit 1
fi

echo "platform=iOS Simulator,id=$udid"
