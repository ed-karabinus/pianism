#!/bin/sh
# Selects the newest stable Xcode installed on a CI runner, and prints its version.
set -eu
xcode=$(ls -d /Applications/Xcode_*.app | grep -vi beta | sort -V | tail -1)
sudo xcode-select -s "$xcode"
xcodebuild -version
