# EPS Quick Look Extension for macOS — Development Specification

> **Document version**: 3.0
> **Target audience**: Mac/iOS developer (mid-level or above) implementing this end-to-end
> **Estimated effort**: 3–4 person-days from zero, split across two stages
> **Deliverable**: Signed, notarized `.dmg` containing a host app + Quick Look Preview Extension that restores Finder spacebar preview for `.eps` and `.ps` files

---

## 1. Goals & Non-Goals

### Goals

1. Pressing **spacebar in Finder** on `.eps` / `.ps` files opens a Quick Look preview, exactly as Preview used to do before macOS Ventura.
2. **Arrow-key navigation** through a multi-file selection feels fluid — no perceptible lag when stepping through previously-viewed files; first view of a new file completes in well under half a second.
3. The package is small and self-contained. Co-authors install once and forget.
4. Compatible with macOS 14 (Sonoma) and later, both Apple Silicon and Intel.
5. Zero third-party runtime dependencies. End users do **not** need TeX Live, TeXShop, Homebrew, or anything else installed.

### Non-Goals

- Editing, annotating, or converting EPS files (the user already has TeXShop for opening/converting).
- Finder thumbnail icons (separate Thumbnail Extension; can be added later if desired).
- App Store distribution.
- Public release. Internal use among a small group of academic co-authors.

### Performance Targets

| Scenario | Target | Rationale |
|----------|--------|-----------|
| Cold render (first view of a file) | ≤ 250 ms p50, ≤ 500 ms p95 | gs process startup ~80 ms, rasterize ~50–150 ms |
| Warm render (cached) | ≤ 30 ms | File I/O + image decode only |
| Extension launch (first spacebar of a session) | ≤ 200 ms | macOS extension process spin-up |
| Memory footprint per extension instance | ≤ 50 MB resident | Quick Look extensions are kept lean by macOS |

---

## 2. Two-Stage Development Strategy

This project is split into two stages with a clear go/no-go gate between them. **Stage A is free and reversible. Stage B costs $99/year and is one-way.** Do not enter Stage B until Stage A's exit criteria are met.

### Stage A — Local development & validation ($0)

**Goal**: Prove on the developer's own Mac that the architecture works end-to-end, including arrow-key navigation performance, before spending any money.

**Tools**: Xcode + free Apple ID (Personal Team).

**Constraints during this stage**:
- App can be built, run, and debugged only on the developer's own Mac (the one Xcode is signed into).
- Cannot be distributed to co-authors yet — Gatekeeper on other Macs will refuse the unsigned bundle.
- Some sandbox edge cases that depend on Developer ID may surface only in Stage B; the PoC in §5 is designed to surface them early.

**Exit criteria** (all must hold before moving to Stage B):
1. PoC in §5 passes — Extension can exec the bundled `gs` from inside its sandbox.
2. Spacebar on `.eps` files in Finder shows the rendered image.
3. Arrow-key navigation across ≥ 10 EPS files feels fluid (subjective but real-world test).
4. Cold-render p50 measured ≤ 300 ms, warm-render p50 ≤ 50 ms (a bit looser than the final targets to account for Debug build overhead).
5. No sandbox violations in Console.app over a 5-minute exercise.

If any of these fail and cannot be fixed within Stage A, **stop**. Re-evaluate the architecture. Do not enrol in Apple Developer Program yet.

### Stage B — Distribution ($99/year)

**Goal**: Take the working Stage A code, apply Developer ID signing, notarize, and distribute to co-authors.

**Tools**: Apple Developer Program membership, `notarytool`.

**Estimated time**: 1 day. Most of the work is already done in Stage A; Stage B is mechanical.

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  EPSQuickLook.app   (host bundle, ~15 MB)                            │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Contents/MacOS/EPSQuickLook                                    │  │
│  │   = SwiftUI shell window. Sole purpose: exist so macOS         │  │
│  │     LaunchServices registers the Extension below.              │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Contents/PlugIns/EPSPreview.appex   (Quick Look Preview Ext)   │  │
│  │                                                                │  │
│  │   ┌──────────────────────────────────────────────────────┐     │  │
│  │   │ Contents/MacOS/EPSPreview                            │     │  │
│  │   │   = QLPreviewingController                           │     │  │
│  │   │     - receives EPS URL from Finder                   │     │  │
│  │   │     - delegates to Renderer actor                    │     │  │
│  │   │     - displays resulting PNG in NSImageView          │     │  │
│  │   └──────────────────────────────────────────────────────┘     │  │
│  │                                                                │  │
│  │   ┌──────────────────────────────────────────────────────┐     │  │
│  │   │ Contents/MacOS/gs                                    │     │  │
│  │   │   = statically-linked Ghostscript universal binary   │     │  │
│  │   │     (arm64 + x86_64), ~12 MB                         │     │  │
│  │   └──────────────────────────────────────────────────────┘     │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘

Cache (per-extension sandbox container):
~/Library/Containers/<ext-bundle-id>/Data/Library/Caches/EPSPreviewCache/
    └── <sha256(path|mtime|size)>.png
```

### Why bundle gs inside the Extension specifically?

Quick Look Preview Extensions run in a strict sandbox. The sandbox allows executing binaries **inside the executing bundle** but blocks arbitrary `Process` exec of system binaries (TeX Live's `gs`, Homebrew's `gs`, etc.) without special entitlements that Apple may not grant during notarization. Placing `gs` inside `EPSPreview.appex/Contents/MacOS/` sidesteps this entirely. It also eliminates dependency on the user's TeX Live state.

### Why PNG rather than PDF?

For Quick Look navigation purposes, a 150 DPI PNG renders 2–3× faster than `pdfwrite` and is decoded by `NSImage` instantly. The user has TeXShop for vector-quality inspection on double-click; spacebar is identification, not analysis.

### Runtime dependencies on end-user Macs

**None.** The shipped app contains everything it needs:
- Ghostscript (bundled, statically linked, universal binary)
- All Swift code compiled in
- Only links against macOS system libraries (`/usr/lib/libSystem.B.dylib`, `/usr/lib/libc++.1.dylib`)

Co-authors do not need TeX Live, TeXShop, Homebrew, Rosetta, or any other tool. They do not need to be on the same macOS minor version as the developer; macOS 14.0 or later is enough.

---

## 4. Prerequisites

### Stage A (free)

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS | 14.0+ on dev machine | Same as deployment target |
| Xcode | 16.0+ | Older may work but untested |
| Apple ID | Any | Free; signed into Xcode under Settings → Accounts → Personal Team |
| Command Line Tools | Latest | `xcode-select --install` |
| Autoconf, automake, libtool, pkg-config | Any recent | `brew install autoconf automake libtool pkg-config` |
| ~2 GB free disk | — | Ghostscript build artifacts |

### Stage B (paid, only when Stage A succeeds)

| Requirement | Version | Notes |
|-------------|---------|-------|
| Apple Developer Program | Active | $99/year, https://developer.apple.com/programs/ |
| Developer ID Application certificate | Valid | Generated via Xcode after Program enrolment |
| App-specific password for notarytool | — | appleid.apple.com → App-Specific Passwords |

Developer should know: Swift, AppKit basics, Xcode target/scheme management, code signing concepts.

---

## 5. Stage A — Phase 0: PoC (the make-or-break test, 0.5 day)

Before writing any of the production code, validate the riskiest assumption: **can a sandboxed Quick Look Preview Extension exec a binary inside its own bundle and write a file to its container's cache directory?** If yes, the rest of the project is mechanical. If no, the architecture must change.

### 5.1 Create a throwaway PoC project

1. Xcode → New → Project → macOS → App, name it `QLProbe`. SwiftUI, Swift, deployment target 14.0.
2. Sign in with free Apple ID under Xcode → Settings → Accounts. Set Signing → "Sign to Run Locally" or use the Personal Team.
3. Add a target → Quick Look Preview Extension → name `QLProbeExt`.

### 5.2 Drop a tiny test binary

Make a shell script behave as a "fake gs" for the PoC. In Terminal:

```bash
cat > /tmp/fake-gs <<'EOF'
#!/bin/bash
# Just create a 1×1 PNG at the requested output path so we can prove
# the exec-and-write path works end-to-end.
OUT=$(echo "$@" | sed -n 's/.*-sOutputFile=\([^ ]*\).*/\1/p')
# 1×1 red PNG, base64-decoded
base64 -D > "$OUT" <<B64
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==
B64
EOF
chmod +x /tmp/fake-gs
```

Add `/tmp/fake-gs` to the `QLProbeExt` target via Build Phases → New Run Script Phase, copying it to `${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/gs` exactly as the production Run Script in §8.3 does.

### 5.3 Minimal Extension code

Replace `PreviewViewController.swift` in `QLProbeExt` with:

```swift
import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() { self.view = NSView(frame: NSRect(x:0,y:0,width:400,height:300)) }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let gs = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/gs")
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let out = cache.appendingPathComponent("probe.png")

        let p = Process()
        p.executableURL = gs
        p.arguments = ["-sOutputFile=\(out.path)", url.path]
        do {
            try p.run()
            p.waitUntilExit()
            NSLog("QLProbe: gs exit=\(p.terminationStatus), wrote=\(FileManager.default.fileExists(atPath: out.path))")
            handler(nil)
        } catch {
            NSLog("QLProbe: exec failed: \(error)")
            handler(error)
        }
    }
}
```

In `Info.plist`, set `QLSupportedContentTypes` to `["com.adobe.encapsulated-postscript"]` (see §8.4).

### 5.4 Run the probe

```bash
xcodebuild -project QLProbe.xcodeproj -scheme QLProbe build
cp -R build/Build/Products/Debug/QLProbe.app /Applications/
open /Applications/QLProbe.app
killall Finder
```

Place any `.eps` file on Desktop, select it, hit spacebar.

### 5.5 Pass criteria

In Console.app, filter by `QLProbe`. You should see:

```
QLProbe: gs exit=0, wrote=true
```

If you see this — **PoC passes. Architecture is sound. Proceed to Phase 1.**

If you see sandbox-violation errors instead (`deny(1) process-exec`, `deny(1) file-write-create`), the architecture needs adjustment. Most likely fixes, in order of preference:

1. Verify the binary really is inside `EPSPreview.appex/Contents/MacOS/`, not elsewhere in the bundle.
2. Verify the binary has `chmod +x`.
3. As a last resort, move the heavy lifting into an XPC service that the host app vends, and have the Extension talk to it via NSXPCConnection. This is more complex but bypasses Extension sandbox limits.

Delete the `QLProbe` project after the PoC. It has done its job.

---

## 6. Stage A — Phase 1: Build Ghostscript as a Static Universal Binary (0.5 day)

### 6.1 Repository layout

```
eps-quicklook/
├── README.md
├── LICENSE                         # AGPL-3.0 (inherited from gs)
├── ghostscript/
│   ├── build-arm64.sh
│   ├── build-x86_64.sh
│   └── build-universal.sh
├── EPSQuickLook.xcodeproj/
├── EPSQuickLook/                   # host app target source
│   ├── EPSQuickLookApp.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   └── EPSQuickLook.entitlements
├── EPSPreview/                     # extension target source
│   ├── PreviewViewController.swift
│   ├── Renderer.swift
│   ├── Info.plist
│   └── EPSPreview.entitlements
└── scripts/
    ├── sign.sh                     # Stage B
    ├── notarize.sh                 # Stage B
    └── package.sh                  # Stage B
```

### 6.2 Download source

```bash
mkdir -p ghostscript && cd ghostscript
GS_VERSION=10.04.0
curl -LO "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10040/ghostscript-${GS_VERSION}.tar.gz"
tar xf "ghostscript-${GS_VERSION}.tar.gz"
mv "ghostscript-${GS_VERSION}" src
```

### 6.3 `ghostscript/build-arm64.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/src"

PREFIX="$PWD/../install-arm64"
rm -rf "$PREFIX"

export CFLAGS="-arch arm64 -O2 -mmacosx-version-min=14.0"
export LDFLAGS="-arch arm64 -mmacosx-version-min=14.0"

./configure \
    --host=aarch64-apple-darwin \
    --prefix="$PREFIX" \
    --disable-cups \
    --disable-dbus \
    --disable-gtk \
    --disable-fontconfig \
    --without-x \
    --without-libidn \
    --without-libpaper \
    --without-pdftoraster \
    --without-tesseract \
    --with-drivers="png16m,pdfwrite,bbox" \
    --enable-static \
    --disable-shared

make clean || true
make -j"$(sysctl -n hw.ncpu)"
make install

echo "arm64 build complete: $PREFIX/bin/gs"
file "$PREFIX/bin/gs"
```

### 6.4 `ghostscript/build-x86_64.sh`

Identical to the above but with `-arch x86_64` and `--host=x86_64-apple-darwin`. On Apple Silicon, this cross-compiles using the native Clang's `-arch` flag.

### 6.5 `ghostscript/build-universal.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

bash build-arm64.sh
bash build-x86_64.sh

mkdir -p universal
lipo -create \
    install-arm64/bin/gs \
    install-x86_64/bin/gs \
    -output universal/gs

# Verify
file universal/gs
lipo -info universal/gs
echo "Universal binary size: $(du -h universal/gs | cut -f1)"

# Sanity test
./universal/gs --version
```

### 6.6 Verification

The resulting binary must be:
- Universal (both architectures) — `file universal/gs` reports `Mach-O universal binary with 2 architectures`
- Statically linked — `otool -L universal/gs` shows only `/usr/lib/libSystem.B.dylib`, `/usr/lib/libc++.1.dylib`, possibly `/usr/lib/libobjc.A.dylib`. **No** `libgs.dylib`, no `/opt/homebrew/...`, no `/usr/local/...`.
- Approximately 10–15 MB
- Functional — `./universal/gs --version` prints the version

If `otool -L` shows external dylib dependencies outside `/usr/lib` and `/System`, the static build did not take effect; re-check configure flags.

---

## 7. Stage A — Phase 2: Xcode Project Setup (0.25 day)

### 7.1 Create the host app

1. Xcode → File → New → Project → macOS → App
2. Product Name: `EPSQuickLook`
3. Team: **Personal Team** (free Apple ID), or your Developer ID team if you happen to be enrolled already
4. Organization Identifier: e.g. `com.<yourdomain>` — final bundle id will be `com.<yourdomain>.EPSQuickLook`
5. Interface: SwiftUI
6. Language: Swift
7. Deployment target: macOS 14.0
8. Save into `eps-quicklook/`

### 7.2 Add the Quick Look Extension target

1. File → New → Target → macOS → Quick Look Preview Extension
2. Product Name: `EPSPreview`
3. Embed in Application: `EPSQuickLook`
4. Bundle Identifier: `com.<yourdomain>.EPSQuickLook.EPSPreview`
5. The template generates `PreviewViewController.swift`, `Info.plist`, and a storyboard. **Delete the storyboard**. We'll build the view programmatically.

### 7.3 Configure both targets

Both targets — `EPSQuickLook` and `EPSPreview`:
- Build Settings → Architectures → Standard Architectures (`arm64 x86_64`)
- Build Settings → Hardened Runtime → **No** during Stage A (Hardened Runtime + Personal Team can fight). **Yes** in Stage B.
- Signing → "Sign to Run Locally" or Personal Team during Stage A; "Developer ID Application" in Stage B.

### 7.4 Run Script Phase to bundle gs

For `EPSPreview` only — Build Phases → New Run Script Phase, **before** "Compile Sources":

```bash
# Copy the universal gs binary into the extension's bundle Contents/MacOS/
GS_SRC="${SRCROOT}/ghostscript/universal/gs"
GS_DST="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/gs"

if [ ! -f "$GS_SRC" ]; then
    echo "error: ghostscript universal binary not found at $GS_SRC"
    echo "error: run ghostscript/build-universal.sh first"
    exit 1
fi

mkdir -p "$(dirname "$GS_DST")"
cp -f "$GS_SRC" "$GS_DST"
chmod +x "$GS_DST"
```

This ensures every build has a fresh `gs` next to the extension binary.

---

## 8. Stage A — Phase 3: Implementation (1.5 days)

The host app's job is to exist on disk so LaunchServices registers the Extension. The Extension does the actual work.

### 8.1 `EPSQuickLook/EPSQuickLookApp.swift`

```swift
import SwiftUI

@main
struct EPSQuickLookApp: App {
    var body: some Scene {
        WindowGroup("EPS Quick Look") {
            ContentView()
                .frame(minWidth: 420, minHeight: 240)
        }
        .windowResizability(.contentSize)
    }
}
```

### 8.2 `EPSQuickLook/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("EPS Quick Look")
                .font(.title2.bold())
            Text("The Finder spacebar preview for .eps and .ps files is now active.\nYou can quit this window — the extension keeps working.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(32)
    }
}
```

### 8.3 `EPSQuickLook/EPSQuickLook.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

### 8.4 `EPSPreview/Renderer.swift`

```swift
import Foundation
import CryptoKit

/// Singleton actor that handles EPS → PNG rasterization with persistent caching.
/// Lifetime spans the extension process, so caching survives across multiple
/// preview requests within a single Quick Look session.
actor Renderer {
    static let shared = Renderer()

    private let cacheDir: URL
    private let gsURL: URL

    /// In-flight rasterizations keyed by cache key, so concurrent requests
    /// for the same file (rare but possible) deduplicate.
    private var inflight: [String: Task<URL, Error>] = [:]

    private init() {
        // Caches directory inside the extension's sandbox container.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("EPSPreviewCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // gs lives next to this extension's executable.
        gsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/gs")
    }

    /// Returns a file URL pointing to a PNG preview for the given EPS/PS file.
    /// Returned PNG is guaranteed to exist on disk on success.
    func png(for source: URL) async throws -> URL {
        let key = try cacheKey(for: source)
        let target = cacheDir.appendingPathComponent("\(key).png")

        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        if let existing = inflight[key] {
            return try await existing.value
        }

        let task = Task<URL, Error> {
            defer { inflight[key] = nil }
            try rasterize(eps: source, to: target)
            return target
        }
        inflight[key] = task
        return try await task.value
    }

    /// SHA256 over (path, mtime, size). Captures content edits without hashing
    /// the file body — important for keeping cache lookup fast on large EPS files.
    private func cacheKey(for url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        let raw = "\(url.path)|\(mtime)|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Synchronous; called inside the actor task.
    private func rasterize(eps: URL, to png: URL) throws {
        let process = Process()
        process.executableURL = gsURL
        process.arguments = [
            "-dNOPAUSE",
            "-dBATCH",
            "-dQUIET",
            "-dSAFER",                      // refuse to read/write outside intended paths
            "-dEPSCrop",                    // crop to BoundingBox
            "-dTextAlphaBits=4",            // smooth text
            "-dGraphicsAlphaBits=4",        // smooth lines
            "-sDEVICE=png16m",
            "-r150",                        // 150 DPI: balance speed and quality
            "-sOutputFile=\(png.path)",
            eps.path,
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()      // discard

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let msg = String(data: data ?? Data(), encoding: .utf8) ?? "gs exited \(process.terminationStatus)"
            // Best-effort cleanup of any partial output.
            try? FileManager.default.removeItem(at: png)
            throw RenderError.ghostscriptFailed(status: process.terminationStatus, stderr: msg)
        }

        guard FileManager.default.fileExists(atPath: png.path) else {
            throw RenderError.outputMissing
        }
    }
}

enum RenderError: LocalizedError {
    case ghostscriptFailed(status: Int32, stderr: String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .ghostscriptFailed(let s, let e):
            return "Ghostscript failed (status \(s)): \(e.prefix(500))"
        case .outputMissing:
            return "Renderer reported success but produced no output file."
        }
    }
}
```

### 8.5 `EPSPreview/PreviewViewController.swift`

```swift
import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private let imageView: NSImageView = {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.imageAlignment = .alignCenter
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let errorLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.alignment = .center
        l.maximumNumberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        l.textColor = .secondaryLabelColor
        return l
    }()

    override func loadView() {
        let root = NSView()
        root.addSubview(imageView)
        root.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: root.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.8),
        ])
        self.view = root
    }

    /// Called by Quick Look for each file as the user navigates with arrow keys.
    /// Same controller instance is reused across calls — that's why our
    /// Renderer is an actor singleton.
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let pngURL = try await Renderer.shared.png(for: url)
                let image = NSImage(contentsOf: pngURL)
                await MainActor.run {
                    self.imageView.image = image
                    self.imageView.isHidden = (image == nil)
                    self.errorLabel.isHidden = true
                    handler(image == nil ? RenderError.outputMissing : nil)
                }
            } catch {
                await MainActor.run {
                    self.imageView.image = nil
                    self.imageView.isHidden = true
                    self.errorLabel.stringValue = error.localizedDescription
                    self.errorLabel.isHidden = false
                    // Still call handler(nil) — we've shown an error message,
                    // and we don't want Quick Look to display a separate failure UI.
                    handler(nil)
                }
            }
        }
    }
}
```

### 8.6 `EPSPreview/Info.plist`

Replace Xcode's generated NSExtension dictionary with:

```xml
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
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
```

### 8.7 `EPSPreview/EPSPreview.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

No special exec entitlement is needed because `gs` is inside the extension's own bundle.

---

## 9. Stage A — Phase 4: Local Test (0.5 day)

### 9.1 Build

```bash
xcodebuild -project EPSQuickLook.xcodeproj \
    -scheme EPSQuickLook \
    -configuration Debug \
    -derivedDataPath build/ \
    build
```

Output: `build/Build/Products/Debug/EPSQuickLook.app`

### 9.2 Verify bundle structure

```bash
APP="build/Build/Products/Debug/EPSQuickLook.app"

# Should list EPSPreview.appex
ls -la "$APP/Contents/PlugIns"

# gs must exist and be executable
file "$APP/Contents/PlugIns/EPSPreview.appex/Contents/MacOS/gs"
"$APP/Contents/PlugIns/EPSPreview.appex/Contents/MacOS/gs" --version
```

### 9.3 Local install + register

```bash
cp -R "$APP" /Applications/
open /Applications/EPSQuickLook.app    # triggers LaunchServices registration
killall Finder                          # nudge Finder to pick up new QL extensions
```

### 9.4 Verify the Extension is loaded

```bash
pluginkit -m -p com.apple.quicklook.preview | grep -i EPSPreview
```

You should see your extension's bundle id with `+` (active). If not, see Troubleshooting §13.

### 9.5 Functional test

In Finder, navigate to a folder of `.eps` files (any Stata `graph export filename.eps` output works). Select one, hit spacebar. The preview should appear within a few hundred milliseconds. Arrow-key through several files; second visits to the same file should be instant.

### 9.6 Performance benchmarking

```bash
EPS=/path/to/sample.eps
GS=/Applications/EPSQuickLook.app/Contents/PlugIns/EPSPreview.appex/Contents/MacOS/gs
TMP=$(mktemp -t bench).png

for i in {1..10}; do
    rm -f "$TMP"
    /usr/bin/time -p "$GS" -dNOPAUSE -dBATCH -dQUIET -dSAFER -dEPSCrop \
        -sDEVICE=png16m -r150 -sOutputFile="$TMP" "$EPS" 2>&1 | grep real
done
```

Targets: median real time < 200 ms on Apple Silicon, < 350 ms on older Intel.

### 9.7 Stage A exit checklist

- [ ] `pluginkit -m` lists the extension as `+` (active)
- [ ] Spacebar on `.eps` shows the rendered preview
- [ ] Arrow keys cycle through 10+ EPS files without stutter on second pass
- [ ] Console.app shows no `sandbox` violations attributed to `EPSPreview`
- [ ] gs benchmark median below targets

If all checked: **Stage A complete.** Decide whether to proceed to Stage B (distribute to co-authors) or use as a personal-only tool.

---

## 10. Stage B — Phase 5: Apple Developer Enrolment & Code Signing (0.5 day)

Only do this section after Stage A's exit checklist is fully green.

### 10.1 Enrol in Apple Developer Program

1. https://developer.apple.com/programs/ → Enroll → ~$99/year
2. Wait for approval (usually 24–48 hours, sometimes immediate)
3. Xcode → Settings → Accounts → re-fetch your team. Your team ID and "Developer ID Application" certificate should now appear.

### 10.2 Reconfigure both targets for distribution

For both `EPSQuickLook` and `EPSPreview`:
- Signing & Capabilities → Team → your paid team
- Signing Certificate → "Developer ID Application"
- Build Settings → Hardened Runtime → **Yes**
- Provisioning Profile → automatic

### 10.3 Rebuild as Release

```bash
xcodebuild -project EPSQuickLook.xcodeproj \
    -scheme EPSQuickLook \
    -configuration Release \
    -derivedDataPath build/ \
    build
```

### 10.4 `scripts/sign.sh`

Xcode signs during build, but the bundled `gs` binary needs explicit re-signing because Run Script Phases run after Xcode's signing pass for that target.

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSQuickLook.app}"
IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)"

EXT="$APP/Contents/PlugIns/EPSPreview.appex"
GS="$EXT/Contents/MacOS/gs"

# 1) Sign the bundled gs binary FIRST (innermost out).
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" \
    "$GS"

# 2) Sign the extension. Its own entitlements must apply.
codesign --force --options runtime --timestamp \
    --entitlements EPSPreview/EPSPreview.entitlements \
    --sign "$IDENTITY" \
    "$EXT"

# 3) Sign the host app last. Do NOT use --deep here; we've already signed nested items.
codesign --force --options runtime --timestamp \
    --entitlements EPSQuickLook/EPSQuickLook.entitlements \
    --sign "$IDENTITY" \
    "$APP"

# 4) Verify the signature graph.
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"
```

A clean run prints `accepted` / `source=Developer ID`.

---

## 11. Stage B — Phase 6: Notarization (0.25 day)

### 11.1 One-time: store credentials

```bash
xcrun notarytool store-credentials "EPS-Notary" \
    --apple-id "<your-apple-id>" \
    --team-id "<TEAM_ID>" \
    --password "<app-specific-password>"
```

App-specific password: appleid.apple.com → Sign-In and Security → App-Specific Passwords.

### 11.2 `scripts/notarize.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSQuickLook.app}"
ZIP="build/EPSQuickLook.zip"

ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
    --keychain-profile "EPS-Notary" \
    --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
```

Successful submission ends with `status: Accepted`. If rejected:

```bash
xcrun notarytool log <submission-id> --keychain-profile "EPS-Notary"
```

Common rejections and fixes:
- "The binary is not signed with a valid Developer ID certificate" → check `codesign -dv $GS`, ensure step 1 of `sign.sh` ran.
- "The signature does not include a secure timestamp" → add `--timestamp` to all `codesign` calls (already in the script).
- "The executable does not have the hardened runtime enabled" → add `--options runtime` (already in the script).

---

## 12. Stage B — Phase 7: Distribution (0.25 day)

### 12.1 `scripts/package.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="build/Build/Products/Release/EPSQuickLook.app"
DMG="build/EPSQuickLook-1.0.dmg"
STAGING="build/dmg-staging"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "EPS Quick Look" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "EPS-Notary" --wait
xcrun stapler staple "$DMG"
```

### 12.2 What to ship to co-authors

```
EPSQuickLook-1.0.dmg               (the binary, signed + notarized)
EPSQuickLook-1.0-source.tar.gz     (this whole repo, for AGPL compliance)
INSTALL.md                          (3-line user instructions)
```

`INSTALL.md`:

```
1. Mount EPSQuickLook-1.0.dmg, drag the app to Applications.
2. Run it once (it will display "extension active" and can be closed).
3. In Finder, press spacebar on any .eps file. That's it.
```

---

## 13. Troubleshooting

### Stage A: Personal Team signing weirdness

- "App is damaged" on first launch: right-click the app → Open → Open. Personal-Team signed apps need this manual override on first run.
- Xcode complains about missing provisioning profile: Signing & Capabilities → toggle "Automatically manage signing" off and on.
- Hardened Runtime causing crashes during Stage A: turn it off in Build Settings → Signing → Enable Hardened Runtime → No. Re-enable in Stage B.

### Extension doesn't appear in `pluginkit`

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain system -domain user
killall Finder
```

If still missing, validate the plist: `plutil -lint EPSPreview/Info.plist`.

### Spacebar shows generic icon, no preview

1. Confirm extension is enabled: System Settings → Privacy & Security → Extensions → Quick Look → check "EPS Preview".
2. Check Console.app, filter by `EPSPreview`. Sandbox violations log here. Most common: `gs` could not exec because it's outside the bundle. Re-verify the Run Script Phase ran.

### gs reports "/invalidfileaccess in --file--"

Sandbox blocked gs from reading the EPS file. The URL passed to `preparePreviewOfFile` should grant access automatically; if it doesn't, wrap the rasterize call with `url.startAccessingSecurityScopedResource()` / `url.stopAccessingSecurityScopedResource()`.

### Notarization stuck "In Progress"

```bash
xcrun notarytool history --keychain-profile "EPS-Notary"
```

Apple's queue is usually 5–30 minutes; if past 1 hour, something is wrong with the submission package (start over).

### "Extension Not Loaded" in System Settings

Open the host app once after each install. macOS only registers extensions whose host app has been launched at least once.

---

## 14. License Compliance Checklist (Stage B only)

Bundling Ghostscript triggers AGPL-3.0 obligations once you start distributing.

- [ ] Repository licensed AGPL-3.0 (root `LICENSE` file copied from the gs source).
- [ ] `README.md` notes "incorporates Ghostscript (AGPL-3.0)" with a link to https://www.ghostscript.com/.
- [ ] Distribution package includes `EPSQuickLook-1.0-source.tar.gz` containing the full Swift source AND build scripts AND the gs source tarball used.
- [ ] Co-authors are explicitly told they may share both the binary and source freely under AGPL terms.
- [ ] Do not redistribute publicly (e.g. on a personal website) unless prepared to maintain the source link permanently.

For an internal academic group, these obligations are routine; treat them like any other internal-tool repo handover.

---

## 15. Effort Breakdown

### Stage A (free, ~3 days)

| Phase | Task | Calendar time |
|-------|------|---------------|
| 0 | PoC: sandboxed extension exec | **0.5 day** ← go/no-go gate |
| 1 | Build static universal gs | 0.5 day |
| 2 | Xcode project skeleton + targets | 0.25 day |
| 3 | Implementation (Renderer + ViewController + host app) | 1.5 days |
| 4 | Local smoke test, perf measurement, sandbox debugging | 0.5 day |
| **Stage A total** | | **~3 days** |

### Stage B (paid, ~1 day, only if Stage A passes)

| Phase | Task | Calendar time |
|-------|------|---------------|
| 5 | Apple Developer enrolment + signing config | 0.5 day (mostly waiting on enrolment) |
| 6 | Notarization | 0.25 day |
| 7 | Packaging, distribution docs | 0.25 day |
| **Stage B total** | | **~1 day** |

**Combined total**: ~4 days of developer effort, $99/year cost, only committed after architecture is proven.

---

## 16. Future Enhancements (out of scope for v1.0)

- Thumbnail Extension target alongside the Quick Look target — Finder icons show actual graph previews instead of generic "ps" icons. Same Renderer can serve both.
- LRU eviction on cache directory once it grows past N MB.
- Configurable DPI via `defaults write com.<yourdomain>.EPSQuickLook.EPSPreview Resolution 200`.
- Multi-page `.ps` viewer with PDF output and PDFView, gated behind a separate UTI handler.
- Pre-warm cache via a Finder Sync extension that watches working directories.

---

## Appendix A — Quick Reference Card

```
Bundle IDs:
  Host:      com.<yourdomain>.EPSQuickLook
  Extension: com.<yourdomain>.EPSQuickLook.EPSPreview

UTIs handled:
  com.adobe.encapsulated-postscript    (.eps)
  com.adobe.postscript                  (.ps)

gs invocation (canonical):
  gs -dNOPAUSE -dBATCH -dQUIET -dSAFER -dEPSCrop \
     -dTextAlphaBits=4 -dGraphicsAlphaBits=4 \
     -sDEVICE=png16m -r150 \
     -sOutputFile=<out.png> <in.eps>

Cache location:
  ~/Library/Containers/<ext-bundle-id>/Data/Library/Caches/EPSPreviewCache/

Cache key:
  sha256("<absolute-path>|<mtime>|<size>")

Performance contract:
  cold render p50  ≤ 250 ms
  warm render p50  ≤ 30 ms
  extension RSS    ≤ 50 MB

Stage transitions:
  Stage A → Stage B gate: §9.7 exit checklist all green
  Stage A: Personal Team, no notarization, dev machine only
  Stage B: Developer ID, hardened runtime, notarized, distributable
```

## Appendix B — End-User Runtime Dependencies

End users (co-authors) installing the final `.dmg` need:

- macOS 14.0 (Sonoma) or later
- That's it.

They do **not** need: TeX Live, TeXShop, MacTeX, Homebrew, Ghostscript, Rosetta 2, Xcode, Python, or any other tool. Everything required is inside the app bundle.
