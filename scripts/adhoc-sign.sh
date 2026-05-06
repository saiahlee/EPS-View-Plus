#!/usr/bin/env bash
# Ad-hoc signs an EPSViewer.app bundle and its embedded extensions and
# helper binaries. The signature is not associated with a certificate
# (--sign "-"), but each component is properly signed and the App Sandbox
# entitlements are reapplied.
#
# This is the standard distribution path for open-source macOS projects
# that don't have an Apple Developer Program membership.

set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSViewer.app}"

if [ ! -d "$APP" ]; then
  echo "error: bundle not found at $APP"
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "── Signing helper binaries ──"

# Sign every dylib first (deepest), then the converter executable.
# This handles both single-file (from-source) and bundled (brew) layouts.
for tools_dir in \
    "$APP/Contents/Tools" \
    "$APP/Contents/PlugIns/EPSPreview.appex/Contents/Tools" \
    "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Tools"; do
  if [ -d "$tools_dir/lib" ]; then
    for dy in "$tools_dir/lib"/*.dylib; do
      [ -f "$dy" ] || continue
      codesign --force --sign "-" --timestamp=none "$dy"
      echo "  signed $dy"
    done
  fi
  if [ -f "$tools_dir/converter" ]; then
    codesign --force --sign "-" --timestamp=none "$tools_dir/converter"
    echo "  signed $tools_dir/converter"
  fi
done

echo
echo "── Signing extensions ──"
codesign --force --sign "-" \
  --entitlements "$REPO_ROOT/EPSPreview/EPSPreview.entitlements" \
  "$APP/Contents/PlugIns/EPSPreview.appex"
echo "  signed EPSPreview.appex"

codesign --force --sign "-" \
  --entitlements "$REPO_ROOT/EPSThumbnail/EPSThumbnail.entitlements" \
  "$APP/Contents/PlugIns/EPSThumbnail.appex"
echo "  signed EPSThumbnail.appex"

echo
echo "── Signing host app ──"
codesign --force --sign "-" \
  --entitlements "$REPO_ROOT/EPSViewer/EPSViewer.entitlements" \
  "$APP"
echo "  signed $APP"

echo
echo "── Verifying signature graph ──"
codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "── Verifying signature graph ──"
# (Sandbox/entitlements check removed — current builds intentionally
# ship without App Sandbox because ad-hoc signing cannot honor the App
# Group entitlement.)

echo
echo "✓ Ad-hoc signing complete."
