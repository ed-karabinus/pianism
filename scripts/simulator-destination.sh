#!/usr/bin/env bash
# Prints an xcodebuild -destination for an available simulator on the newest iOS runtime.
# Usage: scripts/simulator-destination.sh [iPhone|iPad]   (default: iPhone)
# Used by the Makefile and CI so neither hard-codes a device name that may not exist.
set -euo pipefail

family="${1:-iPhone}"
if [[ "$family" != "iPhone" && "$family" != "iPad" ]]; then
  echo "Unknown device family '$family'; use iPhone or iPad." >&2
  exit 2
fi

udid=$(xcrun simctl list devices available --json | jq -r --arg family "$family" '
  [.devices | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-"))
    | {runtime: (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)), device: .value[]}
    | select(.device.name | startswith($family))]
  | sort_by(.runtime) | last | .device.udid // empty')

if [[ -z "$udid" ]]; then
  echo "No available $family simulator found. Install one with: xcodebuild -downloadPlatform iOS" >&2
  exit 1
fi

echo "platform=iOS Simulator,id=$udid"
