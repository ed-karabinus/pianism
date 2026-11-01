#!/bin/zsh
# Runs only the given UI tests on the iPhone simulator, as make test-app does.
# WT picks the checkout to test; the default is the one this script lives in.
cd "${WT:-$(cd "$(dirname "$0")/../.." && pwd)}" || exit 1
dest="$(scripts/simulator-destination.sh ${DEVICE:-iPhone})" || exit 1
udid="${dest##*id=}"
scripts/fail-on-warnings.sh xcodebuild build-for-testing -project Pianism.xcodeproj -scheme Pianism -destination "$dest" SWIFT_SUPPRESS_WARNINGS=NO -quiet || exit 1
app="$(xcodebuild -showBuildSettings -project Pianism.xcodeproj -scheme Pianism -destination 'generic/platform=iOS Simulator' 2>/dev/null | awk '$1 == "CODESIGNING_FOLDER_PATH" {print $3}')"
xcrun simctl bootstatus "$udid" -b >/dev/null && xcrun simctl install "$udid" "$app" && xcrun simctl shutdown "$udid" && xcrun simctl bootstatus "$udid" -b >/dev/null || exit 1
rm -rf build/results/e2e-$1.xcresult
only=()
for t in "${@:2}"; do only+=(-only-testing:"PianismUITests/PracticeTests${t:+/$t}"); done
xcodebuild test-without-building -project Pianism.xcodeproj -scheme Pianism -destination "$dest" \
  -resultBundlePath build/results/e2e-$1.xcresult -collect-test-diagnostics never "${only[@]}" SWIFT_SUPPRESS_WARNINGS=NO
rc=$?
xcrun simctl shutdown "$udid"
exit $rc
