#!/bin/bash
# Fails if any code is unused (ADR 0005). Periphery is pinned by version and checksum, and kept
# in build/, so nothing is installed system-wide. Settings live in .periphery.yml.
set -euo pipefail

version=3.8.0
sha256=07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7
dir=build/periphery-$version

if [ ! -x "$dir/periphery" ]; then
    mkdir -p "$dir"
    curl --fail --silent --show-error --location --output "$dir/periphery.zip" \
        "https://github.com/peripheryapp/periphery/releases/download/$version/periphery-$version.zip"
    echo "$sha256  $dir/periphery.zip" | shasum --algorithm 256 --check --quiet
    unzip -q -o "$dir/periphery.zip" -d "$dir"
fi

"$dir/periphery" scan --strict "$@"
