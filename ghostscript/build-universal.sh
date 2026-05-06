#!/usr/bin/env bash
# Produces ghostscript/universal/ — the directory the Xcode build phase
# copies into each app/extension's Contents/Tools/.
#
# Two strategies, picked by environment variable:
#
#   (default)                          → bundle Homebrew's gs (recommended)
#   EPS_GS_BUILD_FROM_SOURCE=1         → build gs from source (hard on
#                                         recent macOS Command Line Tools
#                                         due to bundled-zlib + clang 21
#                                         interactions; kept for the
#                                         AGPL-purist path)
#
# We default to the brew-bundle path because it's reliable across recent
# macOS versions and gets us building today. The from-source path remains
# available so AGPL-conscientious contributors can produce a fully
# auditable binary chain.

set -euo pipefail

cd "$(dirname "$0")"

if [ "${EPS_GS_BUILD_FROM_SOURCE:-0}" = "1" ]; then
    echo "── Building Ghostscript from source (universal arm64+x86_64) ──"
    echo "   Note: this path requires recent macOS toolchain compatibility."
    echo "   If it fails, retry without EPS_GS_BUILD_FROM_SOURCE set."
    echo

    bash build-arm64.sh
    bash build-x86_64.sh

    mkdir -p universal

    lipo -create \
        install-arm64/bin/gs \
        install-x86_64/bin/gs \
        -output universal/converter

    chmod +x universal/converter

    echo
    echo "─── Universal binary ───"
    file universal/converter
    lipo -info universal/converter
    echo
    echo "─── Linkage ───"
    otool -L universal/converter
    echo
    echo "─── Smoke test ───"
    universal/converter --version

    echo
    echo "✓ universal/converter ready (size: $(du -h universal/converter | cut -f1))"
else
    echo "── Bundling Homebrew Ghostscript ──"
    echo "   (Set EPS_GS_BUILD_FROM_SOURCE=1 to build from source instead.)"
    echo

    bash bundle-from-brew.sh
fi
