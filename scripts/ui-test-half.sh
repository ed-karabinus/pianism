#!/bin/sh
# Prints the xcodebuild flags that run half of the end-to-end tests: half 1 is every other test, sorted by class and
# name, and half 2 is all the rest. Half 2 skips half 1's list rather than naming its own, so a test this misses
# (say, one in a new kind of declaration) runs in half 2 instead of nowhere. On #242's CI runs, the halves' test times
# were within six minutes of each other.
set -eu
case "${1:-}" in
1) flag=only ;;
2) flag=skip ;;
*)
	echo "usage: $0 1|2" >&2
	exit 64
	;;
esac
cd "$(dirname "$0")/../AppUITests"
awk '/^(final )?class [A-Za-z0-9_]+/ { class = $0; sub(/^(final )?class /, "", class); sub(/[^A-Za-z0-9_].*/, "", class) }
	/func test[A-Za-z0-9_]+\(/ { test = $0; sub(/.*func /, "", test); sub(/\(.*/, "", test); print class "/" test }' ./*.swift |
	sort | awk -v flag="$flag" 'NR % 2 == 1 { printf "-%s-testing:PianismUITests/%s ", flag, $0 }'
