#!/usr/bin/env bash
# Verifies the layout of a built EPSViewer.app bundle.
# Useful as a CI smoke test and post-build sanity check.

set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSViewer.app}"

if [ ! -d "$APP" ]; then
  echo "error: bundle not found at $APP"
  exit 2
fi

ok() { printf "  ✓ %s\n" "$1"; }
fail() { printf "  ✗ %s\n" "$1"; FAIL=1; }

FAIL=0

echo "── Top-level structure ──────────────────────────────────────────────"
[ -d "$APP/Contents/MacOS" ]  && ok "Contents/MacOS"  || fail "Contents/MacOS missing"
[ -d "$APP/Contents/Tools" ]  && ok "Contents/Tools"  || fail "Contents/Tools missing"
[ -d "$APP/Contents/PlugIns" ] && ok "Contents/PlugIns" || fail "Contents/PlugIns missing"

echo
echo "── Converter binaries ──────────────────────────────────────────────"
for bundle in \
    "$APP" \
    "$APP/Contents/PlugIns/EPSPreview.appex" \
    "$APP/Contents/PlugIns/EPSThumbnail.appex"; do
  c="$bundle/Contents/Tools/converter"
  if [ -x "$c" ]; then
    arches=$(lipo -info "$c" 2>/dev/null | sed 's/^.*: //')
    ok "$(basename "$bundle"): converter present ($arches)"
  else
    fail "$(basename "$bundle"): converter missing or not executable at $c"
  fi
  # If a lib/ folder exists (Homebrew-bundled gs path), make sure the
  # converter's @rpath dependencies are present.
  libdir="$bundle/Contents/Tools/lib"
  if [ -d "$libdir" ]; then
    n=$(find "$libdir" -name '*.dylib' | wc -l | tr -d ' ')
    ok "$(basename "$bundle"): Tools/lib/ present with $n dylib(s)"
  fi
done

echo
echo "── Code signature ──────────────────────────────────────────────────"
if codesign --verify --deep --strict --verbose=2 "$APP" 2>/dev/null; then
  ok "codesign verify --deep --strict passed"
else
  fail "codesign verify --deep --strict failed"
fi

echo
echo "── Entitlements (host app) ─────────────────────────────────────────"
ent_dump="$(codesign -d --entitlements - "$APP" 2>&1)"
if echo "$ent_dump" | grep -q "group.io.github.saiahlee.EPSViewer"; then
  ok "App Group entitlement present"
else
  fail "App Group entitlement missing"
  echo "    --- codesign -d --entitlements - output ---"
  echo "$ent_dump" | sed 's/^/    /'
fi

echo
if [ "${FAIL:-0}" -eq 0 ]; then
  echo "✓ Bundle verification passed."
else
  echo "✗ Bundle verification FAILED."
  exit 1
fi
