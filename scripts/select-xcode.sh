#!/bin/sh
# Selects the newest stable Xcode installed on a CI runner, and prints its version.
set -eu
# Real folders only: an image's plain names, such as Xcode_27.2.app, can be links to a beta. Betas
# and release candidates aren't stable.
xcode=$(find /Applications -maxdepth 1 -type d -name 'Xcode_*.app' ! -iname '*beta*' ! -iname '*candidate*' | sort -V | tail -1)
sudo xcode-select -s "$xcode"
xcodebuild -version
