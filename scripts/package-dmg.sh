#!/usr/bin/env bash
# Packages an EPSViewer.app into a distributable .dmg.

set -euo pipefail

APP="${1:-build/Build/Products/Release/EPS View+.app}"
# Fallback for older callers that still pass EPSViewer.app
[ -d "$APP" ] || APP="${APP%/EPSViewer.app}/EPS View+.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "dev")}"
OUT_DIR="${OUT_DIR:-out}"
DMG="$OUT_DIR/EPS-View-Plus-$VERSION.dmg"

if [ ! -d "$APP" ]; then
  echo "error: bundle not found at $APP"
  exit 2
fi

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Preserve the bundle name so Finder/Dock see "EPS View+"
cp -R "$APP" "$TMP/EPS View+.app"
ln -s /Applications "$TMP/Applications"

# Drop a small README into the .dmg root for first-run instructions
cat > "$TMP/Read me first.txt" <<EOF
EPS View+ ${VERSION}

Install:
  Drag "EPS View+.app" into the Applications folder.

First launch (one-time, because this build is ad-hoc signed):
  Right-click "EPS View+.app" → Open → Open in the dialog.
Or, from Terminal:
  xattr -dr com.apple.quarantine "/Applications/EPS View+.app"

Quick Look note:
  In v1.0 the bundled Quick Look extension is inactive on macOS due to
  ad-hoc signing limitations. For Finder spacebar previews of EPS files,
  pair this app with Anybox EPS Preview (App Store, \$6.99). EPS View+
  handles double-click, zoom/pan, drag-and-drop, and PDF/PNG export.

Source code & docs: https://github.com/saiahlee/EPS-View-Plus
License: GNU AGPL v3.0
EOF

rm -f "$DMG"
hdiutil create \
  -volname "EPS View+ ${VERSION}" \
  -srcfolder "$TMP" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "✓ Created $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
