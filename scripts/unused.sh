#!/bin/bash
# Fails on unused code in the app and the package code it builds (ADR 0005). Periphery is pinned
# by version and checksum and kept in build/, so nothing is installed system-wide. Settings live in
# .periphery.yml.
set -euo pipefail

version=3.8.0
sha256=07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7
dir=build/periphery-$version

# Only a complete, verified copy gets the final name, so an interrupted run never leaves a broken one.
if [ ! -d "$dir" ]; then
    rm -rf "$dir.partial" && mkdir -p "$dir.partial"
    curl --fail --silent --show-error --location --output "$dir.partial/periphery.zip" \
        "https://github.com/peripheryapp/periphery/releases/download/$version/periphery-$version.zip"
    echo "$sha256  $dir.partial/periphery.zip" | shasum --algorithm 256 --check --quiet
    unzip -q "$dir.partial/periphery.zip" -d "$dir.partial"
    mv "$dir.partial" "$dir"
fi

"$dir/periphery" scan --strict
