#!/usr/bin/env bash
# Prints an xcodebuild -destination for an available simulator on the newest iOS runtime, or the newest
# that matches a version such as 26 or 27.0.
# Usage: scripts/simulator-destination.sh [iPhone|iPad] [iOS version]   (default: iPhone, newest)
# Used by the Makefile and CI so neither hard-codes a device name that may not exist.
set -euo pipefail

family="${1:-iPhone}"
version="${2:-}"
if [[ "$family" != "iPhone" && "$family" != "iPad" ]]; then
  echo "Unknown device family '$family'; use iPhone or iPad." >&2
  exit 2
fi

udid=$(xcrun simctl list devices available --json | jq -r --arg family "$family" --arg version "$version" '
  [.devices | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-"))
    | (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-")) as $parts
    | select($version == "" or ($parts | join(".")) == $version or ($parts | join(".") | startswith($version + ".")))
    | {runtime: ($parts | map(tonumber)), device: .value[]}
    | select(.device.name | startswith($family))]
  | sort_by(.runtime) | last | .device.udid // empty')

if [[ -z "$udid" ]]; then
  echo "No available $family simulator found${version:+ on iOS $version}. Install one with: xcodebuild -downloadPlatform iOS" >&2
  exit 1
fi

echo "platform=iOS Simulator,id=$udid"
