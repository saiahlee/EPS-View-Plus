# Building EPS Viewer from source

## Requirements

- macOS 14.0 or later (Sonoma+)
- Xcode 16.0 or later (with Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- (Optional) [`xcbeautify`](https://github.com/cpisciotta/xcbeautify) for nicer build output: `brew install xcbeautify`
- ~30 minutes (mostly waiting for Ghostscript to compile)

## One-shot build

```bash
git clone https://github.com/saiahlee/EPS-View-Plus
cd EPSViewer
bash scripts/build-app.sh
```

This produces `build/Build/Products/Release/EPSViewer.app` and `out/EPSViewer-<version>.dmg`.

## Step by step

### 1. Build Ghostscript universal binary

This is the slowest step (~25 minutes on a modern Mac):

```bash
cd ghostscript
bash build-universal.sh
cd ..
```

You should now have `ghostscript/universal/converter`. Quick sanity check:

```bash
file ghostscript/universal/converter
ghostscript/universal/converter --version
```

### 2. Generate the Xcode project

```bash
xcodegen generate
```

This reads `project.yml` and produces `EPSViewer.xcodeproj`. The Xcode project is regeneratable, so don't commit it.

### 3. Build in Xcode

```bash
open EPSViewer.xcodeproj
```

Or from the command line:

```bash
xcodebuild \
  -project EPSViewer.xcodeproj \
  -scheme EPSViewer \
  -configuration Release \
  -derivedDataPath build/ \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### 4. Ad-hoc sign

```bash
bash scripts/adhoc-sign.sh build/Build/Products/Release/EPSViewer.app
```

### 5. Verify

```bash
bash scripts/verify-bundle.sh build/Build/Products/Release/EPSViewer.app
```

### 6. (Optional) Package DMG

```bash
bash scripts/package-dmg.sh build/Build/Products/Release/EPSViewer.app
```

Outputs to `out/EPSViewer-<version>.dmg`.

## Installing your local build

```bash
cp -R build/Build/Products/Release/EPSViewer.app /Applications/
open /Applications/EPSViewer.app
killall Finder    # so Finder picks up the new Quick Look extension
```

To confirm the extensions registered:

```bash
pluginkit -m -p com.apple.quicklook.preview   | grep EPSViewer
pluginkit -m -p com.apple.quicklook.thumbnail | grep EPSViewer
```

## Troubleshooting

### "No converter binary found" warnings during build

The Run Script Phase that copies `Tools/converter` into each bundle gracefully no-ops if the universal binary is missing. The app builds, but Quick Look and the viewer will fail at runtime. Fix by running `bash ghostscript/build-universal.sh`.

### Quick Look extension doesn't appear after install

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain system -domain user
killall Finder
```

Then re-open the host app once. Confirm via System Settings → Privacy & Security → Extensions → Quick Look.

### "App is damaged and can't be opened"

This is Gatekeeper rejecting an ad-hoc signed download. Either right-click → Open or:

```bash
xattr -dr com.apple.quarantine /Applications/EPSViewer.app
```
