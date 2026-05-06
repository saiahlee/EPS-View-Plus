#!/usr/bin/env bash
# End-to-end local build:
#   1. Build Ghostscript universal binary (if not already built)
#   2. Force-write entitlements files (Xcode 26 has been observed to
#      empty them in unprovisioned ad-hoc builds)
#   3. Generate Xcode project from project.yml
#   4. xcodebuild Release
#   5. Ad-hoc sign (entitlements re-applied here too, as a belt-and-braces)
#   6. Package DMG
#
# Idempotent — safe to re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "── (1/5) Ghostscript ──"
if [ ! -x "ghostscript/universal/converter" ]; then
  bash ghostscript/build-universal.sh
else
  echo "✓ ghostscript/universal/converter already present"
fi

echo
echo "── (1.5/5) Building AppIcon.icns from AppIcon.png ──"
# Prefer the in-repo icon at EPSViewer/AppIcon.png so anyone cloning the
# repository can reproduce the app icon. Fall back to the legacy
# out-of-repo location for backwards compatibility.
if [ -f "$REPO_ROOT/EPSViewer/AppIcon.png" ]; then
  ICON_SRC="$REPO_ROOT/EPSViewer/AppIcon.png"
elif [ -f "$REPO_ROOT/../icon.png" ]; then
  ICON_SRC="$REPO_ROOT/../icon.png"
else
  ICON_SRC=""
fi
ICON_DST="$REPO_ROOT/EPSViewer/AppIcon.icns"
if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  # Apple expects these specific sizes inside an .iconset directory.
  for spec in \
    "16x16:icon_16x16.png" \
    "32x32:icon_16x16@2x.png" \
    "32x32:icon_32x32.png" \
    "64x64:icon_32x32@2x.png" \
    "128x128:icon_128x128.png" \
    "256x256:icon_128x128@2x.png" \
    "256x256:icon_256x256.png" \
    "512x512:icon_256x256@2x.png" \
    "512x512:icon_512x512.png" \
    "1024x1024:icon_512x512@2x.png"; do
    size="${spec%%:*}"
    name="${spec##*:}"
    sips -z "${size%x*}" "${size%x*}" "$ICON_SRC" --out "$ICONSET/$name" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON_DST"
  rm -rf "$(dirname "$ICONSET")"
  echo "  wrote $ICON_DST"
else
  echo "  warn: $ICON_SRC not found — icon will fall back to system default"
fi

echo
echo "── (2/5) Refreshing entitlements + XcodeGen ──"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed. Install with: brew install xcodegen"
  exit 1
fi

# Always re-write the entitlements files. Xcode 26's build phase has been
# observed to overwrite them with an empty <dict/> for unprovisioned
# ad-hoc builds. Pinning the contents here makes every build deterministic.
write_entitlements_host() {
  # Host app: no sandbox (App Group can't be honored without a Dev team).
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF
  echo "  wrote $1 (host, no sandbox)"
}

write_entitlements_extension() {
  # We initially had app-sandbox=true here (Quick Look extensions
  # nominally require it), but macOS 26's sandbox blocks our bundled
  # converter binary's exec/dylib loads even though everything sits
  # inside the .appex itself. Without an Apple Developer Program team
  # we can't grant the needed temporary-exception entitlements that
  # would unblock it, so we ship the extensions unsandboxed. Quick Look
  # registration still works — the sandbox key is not load-bearing for
  # registration, only for runtime privilege restriction.
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF
  echo "  wrote $1 (extension, unsandboxed)"
}

write_entitlements_host       EPSViewer/EPSViewer.entitlements
write_entitlements_extension  EPSPreview/EPSPreview.entitlements
write_entitlements_extension  EPSThumbnail/EPSThumbnail.entitlements

# ── Force-write the three Info.plist files ────────────────────────────────
# Xcode 26 has been observed to "tidy" Info.plist files on first build by
# stripping NSExtension blocks and rewriting them in compact tab-indented
# form. That breaks our Quick Look / Thumbnail extension registrations
# silently. Pin the source of truth here on every run.

write_host_info_plist() {
  cat > EPSViewer/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>EPS View+</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>EPS View+</string>
    <key>CFBundleSpokenName</key>
    <string>EPS View Plus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © EPS Viewer contributors. Licensed under AGPL-3.0.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Encapsulated PostScript</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.encapsulated-postscript</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PostScript</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.postscript</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
EOF
  echo "  wrote EPSViewer/Info.plist"
}

write_preview_info_plist() {
  cat > EPSPreview/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>EPS Preview</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>com.adobe.encapsulated-postscript</string>
                <string>com.adobe.postscript</string>
            </array>
            <key>QLSupportsSearchableItems</key>
            <false/>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.preview</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PreviewViewController</string>
    </dict>
</dict>
</plist>
EOF
  echo "  wrote EPSPreview/Info.plist"
}

write_thumbnail_info_plist() {
  cat > EPSThumbnail/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>EPS Thumbnail</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>com.adobe.encapsulated-postscript</string>
                <string>com.adobe.postscript</string>
            </array>
            <key>QLThumbnailMinimumSize</key>
            <integer>16</integer>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.thumbnail</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ThumbnailProvider</string>
    </dict>
</dict>
</plist>
EOF
  echo "  wrote EPSThumbnail/Info.plist"
}

write_host_info_plist
write_preview_info_plist
write_thumbnail_info_plist

xcodegen generate

echo
echo "── (3/5) xcodebuild Release ──"
xcodebuild \
  -project EPSViewer.xcodeproj \
  -scheme EPSViewer \
  -configuration Release \
  -derivedDataPath build/ \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  build | xcbeautify || true   # xcbeautify is optional

APP="build/Build/Products/Release/EPSViewer.app"
if [ ! -d "$APP" ]; then
  echo "error: build did not produce $APP"
  exit 1
fi

echo
echo "── (3.5/5) Patching Info.plist files in built bundle ──"
# Even with NSExtension in our source Info.plist, Xcode 26 has been seen
# to omit the block from the final built .appex Info.plist. Patch the
# built copies directly using PlistBuddy so registration works.

PREVIEW_PLIST="$APP/Contents/PlugIns/EPSPreview.appex/Contents/Info.plist"
THUMB_PLIST="$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Info.plist"

patch_extension_plist() {
  local plist="$1"
  local point="$2"            # com.apple.quicklook.preview / .thumbnail
  local principal="$3"        # full module-qualified class name

  if [ ! -f "$plist" ]; then
    echo "  warn: $plist missing — skipping"
    return
  fi

  # Idempotent: clear any existing NSExtension first
  /usr/libexec/PlistBuddy -c "Delete :NSExtension" "$plist" 2>/dev/null || true

  /usr/libexec/PlistBuddy \
    -c "Add :NSExtension dict" \
    -c "Add :NSExtension:NSExtensionPointIdentifier string $point" \
    -c "Add :NSExtension:NSExtensionPrincipalClass string $principal" \
    -c "Add :NSExtension:NSExtensionAttributes dict" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes array" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:0 string com.adobe.encapsulated-postscript" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:1 string com.adobe.postscript" \
    "$plist"

  if [ "$point" = "com.apple.quicklook.preview" ]; then
    /usr/libexec/PlistBuddy \
      -c "Add :NSExtension:NSExtensionAttributes:QLSupportsSearchableItems bool false" \
      "$plist"
  else
    /usr/libexec/PlistBuddy \
      -c "Add :NSExtension:NSExtensionAttributes:QLThumbnailMinimumSize integer 16" \
      "$plist"
  fi

  echo "  patched $plist"
}

# NSExtensionPrincipalClass uses "<ModuleName>.<ClassName>". Our extension
# targets are named EPSPreview and EPSThumbnail, so the module names match.
patch_extension_plist "$PREVIEW_PLIST" "com.apple.quicklook.preview"   "EPSPreview.PreviewViewController"
patch_extension_plist "$THUMB_PLIST"   "com.apple.quicklook.thumbnail" "EPSThumbnail.ThumbnailProvider"

echo
echo "── (3.55/5) Forcing display name in built Info.plist ──"
# Xcode resolves $(PRODUCT_NAME) → "EPSViewer" at build time, which makes
# the menu bar / Dock label "EPSViewer". We override the user-visible
# name fields directly in the built Info.plist:
#   CFBundleDisplayName  = "EPS View+"  → Finder + Dock + Window title
#   CFBundleName         = "EPS View+"  → menu bar's first menu, About box
#   CFBundleSpokenName   = "EPS View Plus"  → VoiceOver / accessibility
#                                              (alternate name with "Plus")
HOST_PLIST="$APP/Contents/Info.plist"
if [ -f "$HOST_PLIST" ]; then
  set_or_add() {
    local key="$1" val="$2" plist="$3"
    /usr/libexec/PlistBuddy -c "Set :$key $val" "$plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :$key string $val" "$plist"
  }
  set_or_add CFBundleDisplayName "EPS View+"      "$HOST_PLIST"
  set_or_add CFBundleName        "EPS View+"      "$HOST_PLIST"
  set_or_add CFBundleSpokenName  "EPS View Plus"  "$HOST_PLIST"
  echo "  CFBundleDisplayName / CFBundleName = 'EPS View+'"
  echo "  CFBundleSpokenName                  = 'EPS View Plus'"
fi

# Localized InfoPlist.strings — Dock and Finder use these *if* present
# and override the values in Info.plist. Xcode auto-generates a stub
# that contains "EPSViewer" (= $(PRODUCT_NAME) at build time), so we
# overwrite it for every locale we support.
echo
echo "── (3.56/5) Writing localized InfoPlist.strings ──"
LPROJS="$APP/Contents/Resources/en.lproj"
mkdir -p "$LPROJS"
cat > "$LPROJS/InfoPlist.strings" <<'EOF'
CFBundleName        = "EPS View+";
CFBundleDisplayName = "EPS View+";
CFBundleSpokenName  = "EPS View Plus";
EOF
# Some macOS builds default to Base.lproj or no locale folder; cover both.
cp -f "$LPROJS/InfoPlist.strings" "$APP/Contents/Resources/InfoPlist.strings" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources/Base.lproj"
cp -f "$LPROJS/InfoPlist.strings" "$APP/Contents/Resources/Base.lproj/InfoPlist.strings"
echo "  wrote en.lproj/InfoPlist.strings + Base.lproj + top-level"

echo
echo "── (3.6/5) Installing AppIcon into built bundle ──"
# XcodeGen / Xcode have inconsistent behavior bundling .icns files placed
# next to source code. Copying the .icns straight into the built app's
# Resources/ folder is the most reliable way to make Finder/Dock pick it
# up. Also force-write the Info.plist's CFBundleIconFile in case Xcode
# rewrote it during build.
ICNS_BUILT="$REPO_ROOT/EPSViewer/AppIcon.icns"
if [ -f "$ICNS_BUILT" ]; then
  cp -f "$ICNS_BUILT" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
  echo "  installed $APP/Contents/Resources/AppIcon.icns"
else
  echo "  warn: $ICNS_BUILT missing — skipping"
fi

# Confirm what landed in the built bundle
echo
echo "── (3.7/5) Bundle name + icon sanity ──"
echo "  Resources/:"
ls -la "$APP/Contents/Resources/" | grep -iE "icon|icns" | sed 's/^/    /' || echo "    (no icons found)"
echo "  Info.plist user-visible fields:"
plutil -p "$APP/Contents/Info.plist" 2>/dev/null | \
  grep -E "CFBundleDisplayName|CFBundleName |CFBundleIcon|CFBundleSpoken" | sed 's/^/    /'

echo
echo "── (4/5) Ad-hoc sign ──"
# Re-write entitlements once more (Xcode's build phase may have wiped
# them again during the build). adhoc-sign.sh reads them via --entitlements.
write_entitlements_host       EPSViewer/EPSViewer.entitlements
write_entitlements_extension  EPSPreview/EPSPreview.entitlements
write_entitlements_extension  EPSThumbnail/EPSThumbnail.entitlements

# Don't abort the whole pipeline if the entitlement-embed check at the end
# of adhoc-sign.sh fails — the app is still usable, the cache just won't
# be App-Group-shared. The user can decide whether to ship as-is.
bash scripts/adhoc-sign.sh "$APP" || \
  echo "⚠️  adhoc-sign reported a problem (likely entitlements). Continuing."

# Rename the bundle directory itself so Finder/Dock fallback paths see
# "EPS View+" rather than "EPSViewer". Codesigning is unaffected by the
# bundle directory name (signature is on the bundle contents).
echo
echo "── (4.5/5) Renaming bundle to 'EPS View+.app' ──"
RENAMED_APP="$(dirname "$APP")/EPS View+.app"
rm -rf "$RENAMED_APP"
mv "$APP" "$RENAMED_APP"
APP="$RENAMED_APP"
echo "  $APP"

echo
echo "── (5/5) Package DMG ──"
bash scripts/package-dmg.sh "$APP"

echo
echo "✓ Build pipeline complete."
echo "  App: $APP"
echo
echo "Install:"
echo "    rm -rf '/Applications/EPS View+.app' /Applications/EPSViewer.app"
echo "    cp -R '$APP' /Applications/"
echo "    xattr -dr com.apple.quarantine '/Applications/EPS View+.app'"
echo "    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R '/Applications/EPS View+.app'"
echo "    killall Finder Dock"
echo
echo "Tip: After installing to /Applications, run these to refresh the"
echo "Dock/Finder labels (otherwise the cached old name may linger):"
echo "    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/EPSViewer.app"
echo "    killall Finder Dock"
