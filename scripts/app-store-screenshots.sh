#!/bin/zsh
# Makes the App Store screenshots (#56) in build/app-store-screenshots/iphone and ipad: ScreenshotTests takes them
# from sample practice on the two sizes App Store Connect asks for, with the status bar at 9:41 on the sample's
# Thursday (an iPad shows the date), then app-store-screenshots.swift puts the headlines on. One simulator run, so
# run it when no other is going.
set -e
cd "$(dirname "$0")/.."
out=build/app-store-screenshots
rm -rf $out
# Each simulator is left as it was, its status bar cleared and shut down, even when a step fails.
cleanup() { [[ -n $udid ]] && { xcrun simctl status_bar $udid clear; xcrun simctl shutdown $udid; } 2>/dev/null; true }
trap cleanup EXIT
for device in "iPhone 18 Pro Max" "iPad Pro 13-inch (M5)"; do
  udid=$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')
  [[ -n $udid ]] || { echo "No $device simulator: add it in Xcode's Devices and Simulators" >&2; exit 1; }
  name=${${device%% *}:l}
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl status_bar $udid override --time 2026-11-12T09:41:00.000-08:00 --dataNetwork wifi --wifiBars 3 --cellularBars 4 \
    --batteryState charged --batteryLevel 100
  TEST_RUNNER_PIANISM_SCREENSHOTS=1 xcodebuild test -project Pianism.xcodeproj -scheme Pianism -destination id=$udid \
    -only-testing:PianismUITests/ScreenshotTests -resultBundlePath $out/$name.xcresult -quiet
  xcrun xcresulttool export attachments --path $out/$name.xcresult --output-path $out/$name-plain >/dev/null
  # Each takes its attachment's name, such as "1 Practice.png".
  python3 - $out/$name-plain <<'PY'
import json, os, sys
folder = sys.argv[1]
for test in json.load(open(os.path.join(folder, "manifest.json"))):
    for shot in test["attachments"]:
        name = shot.get("suggestedHumanReadableName", "").split("_0_")[0]
        if name[:1].isdigit():
            os.rename(os.path.join(folder, shot["exportedFileName"]), os.path.join(folder, name + ".png"))
PY
  swift scripts/app-store-screenshots.swift $out/$name-plain $out/$name
  cleanup
done
