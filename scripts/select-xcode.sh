#!/bin/sh
# Selects the newest stable Xcode installed on a CI runner, and prints its version.
set -eu
# Folders named for a version only: betas and release candidates have a suffix, and an image's
# plain names, such as Xcode_27.2.app, can be links to a beta.
xcode=$(find -E /Applications -maxdepth 1 -type d -regex '.*/Xcode_[0-9.]+\.app' | sort -V | tail -1)
sudo xcode-select -s "$xcode"
xcodebuild -version
