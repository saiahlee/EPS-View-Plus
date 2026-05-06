# EPS Viewer for macOS — Open Source Development Specification

> **Document version**: 4.0
> **License**: AGPL-3.0 (inherited from bundled Ghostscript)
> **Distribution**: GitHub repository, public, free
> **Apple Developer Program**: not required
> **Target audience**: Mac/iOS developer (mid-level or above) implementing this end-to-end
> **Estimated effort**: 5–7 person-days from zero

---

## 1. Project Overview

EPS Viewer is an open-source macOS application that restores and extends the EPS/PostScript handling that Apple removed from Preview starting with macOS Ventura. It provides:

- **Quick Look preview** (Finder spacebar) — fast enough to fly through a folder of EPS files with arrow keys
- **Thumbnail generation** in Finder, so EPS icons show actual graph previews
- **Dedicated viewer window** with zoom and pan, opened by double-clicking an `.eps` or `.ps` file
- **Export** to PNG (configurable DPI) or PDF

The app bundles a statically-linked Ghostscript universal binary; end users have **zero runtime dependencies** beyond macOS itself.

### Architectural lineage

This design draws explicitly from the structure of **Anybox Ltd's EPS Preview** ($6.99 commercial app), which we analyzed via `otool -L` and `find` on its bundle. Anybox's structure validated several decisions we had been considering:

| Decision | Anybox EPS Preview | This project |
|----------|-------------------|--------------|
| Render pipeline | PDF (uses `PDFKit.framework`) | PDF (same) |
| Helper binary location | `Contents/Tools/converter` | `Contents/Tools/converter` (same) |
| Extension topology | PreviewExtension.appex + ThumbnailExtension.appex | Same two extensions |
| Cache key strategy | (CryptoKit linkage suggests SHA-based) | SHA256(path \| mtime \| size) |
| Auto-update | Sparkle 2.x with XPC services | Sparkle 2.x (optional, added in §13) |
| Open/zoom/export | Not provided | **Provided** (this project's differentiator) |
| Distribution | Paid, direct download | Free, GitHub, AGPL source available |

Anybox's app does only the Quick Look + Thumbnail half. This project adds the viewer window, zoom, and export — the parts that the deprecated macOS Preview app used to provide for free.

---

## 2. Goals & Non-Goals

### Goals

1. **Spacebar Quick Look** in Finder for `.eps` and `.ps`, fast enough that arrow-key navigation through tens of files feels instantaneous.
2. **Finder thumbnails** showing actual rendered preview, not generic file-type icons.
3. **Double-click opens** in a dedicated viewer window with smooth zoom and pan.
4. **Export** menu items for PNG (with DPI selector) and PDF.
5. **Open source under AGPL-3.0**, hosted on GitHub.
6. Self-contained: no TeX Live, no Homebrew, no Rosetta required by end users.
7. No commercial agreements: contributors and users alike can build, audit, fork.

### Non-Goals

- Editing or annotation of EPS content.
- Multi-page PostScript navigation (first page only in v1; could be added later).
- App Store distribution (incompatible with AGPL bundling).
- Apple Developer Program membership; we use ad-hoc signing for direct downloads.

### Performance Targets

| Scenario | Target | Notes |
|----------|--------|-------|
| Cold render (first preview of a file) | ≤ 250 ms p50, ≤ 500 ms p95 | gs startup ~80 ms + render ~50–150 ms |
| Warm Quick Look (PDF cached) | ≤ 30 ms | PDFKit decode of small PDF |
| Extension launch (first spacebar of session) | ≤ 200 ms | macOS extension process spin-up |
| Memory in extension | ≤ 50 MB resident | Quick Look extensions are kept lean by macOS |
| Host window cold open | ≤ 500 ms | Render + window creation |
| Export PNG (300 DPI, average graph) | ≤ 500 ms | gs re-render at higher resolution |

The cache hit rate is the main lever. Once a file has been viewed (in any of: Quick Look, thumbnail, host window), all other views become warm thanks to the App Group shared cache.

---

## 3. Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│  EPSViewer.app   (host bundle, ~18 MB)                                 │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Contents/MacOS/EPSViewer                                         │  │
│  │   = SwiftUI + AppKit host                                        │  │
│  │     - main viewer window (PDFView, zoom, pan)                    │  │
│  │     - file open handler (UTI-registered for .eps / .ps)          │  │
│  │     - Export menu (PNG / PDF)                                    │  │
│  │     - drag-drop receiver                                         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Contents/Tools/converter                                         │  │
│  │   = statically-linked Ghostscript universal binary               │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Contents/PlugIns/EPSPreview.appex                                │  │
│  │   - QLPreviewingController                                       │  │
│  │   - shows cached PDF in PDFView (zoomable inside Quick Look)     │  │
│  │   - Contents/Tools/converter (its own copy)                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Contents/PlugIns/EPSThumbnail.appex                              │  │
│  │   - QLThumbnailProvider                                          │  │
│  │   - generates Finder icon thumbnails                             │  │
│  │   - Contents/Tools/converter (its own copy)                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Shared App Group container                                   │
   │ ~/Library/Group Containers/<group-id>/EPSViewerCache/        │
   │   └── <sha256(path|mtime|size)>.pdf                          │
   │                                                              │
   │ Read/written by ALL THREE targets above. A file rendered     │
   │ when opened in the host window is instantly available to     │
   │ Finder spacebar Quick Look — and vice versa.                 │
   └──────────────────────────────────────────────────────────────┘
```

### Why three separate copies of `gs`?

Each `.appex` extension and the host app run in their own sandbox. The sandbox permits exec of binaries **inside the calling bundle** but not arbitrary cross-bundle exec. So each target carries its own `gs`. This costs ~36 MB total (3 × 12 MB) but eliminates an entire class of sandbox-exec headaches.

(In an XPC-service-based design we could share one `gs`, but that's significant additional complexity for one-time disk savings.)

### Why PDF as the canonical render output?

A single artifact serves four use cases:

1. **Quick Look display** — `PDFView` renders cached PDF with zoom-in-Quick-Look "for free" (PDFKit handles vector zoom natively).
2. **Thumbnail generation** — `QLThumbnailProvider` rasterizes a CGContext from the first page of the PDF.
3. **Host window viewer** — same `PDFView`, just in a larger window with toolbar.
4. **Export PDF** — direct file copy from cache to user's chosen location.
5. **Export PNG** — re-run gs at user-specified DPI, since PDFs scale better than re-rasterizing a low-DPI PNG up.

PNG would have been faster for cold renders (~30% less gs work), but the PDF path's **artifact reuse across all features** more than makes up for it. Plus PDFKit decodes cached PDFs in milliseconds.

### Why an App Group?

Without it, each of the three targets has its own private cache. A file previewed via spacebar wouldn't help when later opened in the host window, and vice versa. With an App Group:

- One render serves all three targets forever (until file mtime changes)
- Opening a folder in the host app effectively pre-warms Finder's Quick Look for that folder
- Cache eviction logic is centralized

App Groups don't require Apple Developer Program for local development — Personal Team accounts can create them for ad-hoc-signed builds. The group identifier just needs to be agreed upon across targets.

---

## 4. Repository Layout

```
eps-viewer/
├── README.md                       # public-facing, with screenshots
├── LICENSE                         # AGPL-3.0 verbatim
├── NOTICE.md                       # third-party attributions (Ghostscript)
├── CHANGELOG.md
├── CONTRIBUTING.md
├── .gitignore
├── .github/
│   ├── workflows/
│   │   ├── build.yml               # CI: build + ad-hoc sign on push
│   │   └── release.yml             # tag-triggered release artifact
│   └── ISSUE_TEMPLATE/
├── docs/
│   ├── architecture.md             # this document, edited for public audience
│   ├── building-from-source.md     # for users who want to verify
│   └── design-decisions.md         # rationale captured for contributors
├── ghostscript/
│   ├── README.md
│   ├── build-arm64.sh
│   ├── build-x86_64.sh
│   ├── build-universal.sh
│   └── .gitignore                  # don't commit gs source or build artifacts
├── EPSViewer.xcodeproj/
├── EPSViewer/                      # host app target
│   ├── EPSViewerApp.swift
│   ├── ViewerWindow.swift
│   ├── ViewerToolbar.swift
│   ├── ExportPanel.swift
│   ├── DocumentOpener.swift
│   ├── Info.plist
│   └── EPSViewer.entitlements
├── EPSPreview/                     # Quick Look extension
│   ├── PreviewViewController.swift
│   ├── Info.plist
│   └── EPSPreview.entitlements
├── EPSThumbnail/                   # Thumbnail extension
│   ├── ThumbnailProvider.swift
│   ├── Info.plist
│   └── EPSThumbnail.entitlements
├── Shared/                         # source files compiled into all 3 targets
│   ├── Renderer.swift              # gs invocation + caching
│   ├── CacheStore.swift            # App Group container management
│   ├── Hashing.swift
│   └── ProcessRunner.swift
└── scripts/
    ├── package-dmg.sh
    ├── adhoc-sign.sh
    └── verify-bundle.sh
```

---

## 5. Phase 1 — Build Ghostscript as a Static Universal Binary

This phase is unchanged from earlier iterations. The output binary will be named `converter` (not `gs`) when copied into the app bundles, matching the Anybox naming convention.

### 5.1 Download source

```bash
mkdir -p ghostscript && cd ghostscript
GS_VERSION=10.04.0
curl -LO "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10040/ghostscript-${GS_VERSION}.tar.gz"
tar xf "ghostscript-${GS_VERSION}.tar.gz"
mv "ghostscript-${GS_VERSION}" src
```

### 5.2 `ghostscript/build-arm64.sh`

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
    --with-drivers="png16m,pdfwrite,bbox,jpeg" \
    --enable-static \
    --disable-shared

make clean || true
make -j"$(sysctl -n hw.ncpu)"
make install
```

### 5.3 `ghostscript/build-x86_64.sh`

Identical with `-arch x86_64` and `--host=x86_64-apple-darwin`.

### 5.4 `ghostscript/build-universal.sh`

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
    -output universal/converter        # note: renamed to "converter"

file universal/converter
lipo -info universal/converter
./universal/converter --version
```

### 5.5 Verification

`otool -L ghostscript/universal/converter` should show only system libraries (`/usr/lib/libSystem.B.dylib`, `/usr/lib/libc++.1.dylib`, possibly `/usr/lib/libobjc.A.dylib`). Approximate size: 10–15 MB.

---

## 6. Phase 2 — Xcode Project Setup

### 6.1 Create the host app

1. Xcode → File → New → Project → macOS → App
2. Product Name: `EPSViewer`
3. Team: **Personal Team** (free Apple ID — no paid program needed)
4. Organization Identifier: `io.github.<your-username>` (matches the public repo)
5. Interface: SwiftUI
6. Language: Swift
7. Deployment target: macOS 14.0

### 6.2 Add Quick Look Preview Extension target

1. File → New → Target → macOS → Quick Look Preview Extension
2. Product Name: `EPSPreview`
3. Embed in Application: `EPSViewer`
4. Bundle Identifier: `io.github.<username>.EPSViewer.EPSPreview`
5. Delete the auto-generated storyboard.

### 6.3 Add Thumbnail Extension target

1. File → New → Target → macOS → Thumbnail Extension
2. Product Name: `EPSThumbnail`
3. Embed in Application: `EPSViewer`
4. Bundle Identifier: `io.github.<username>.EPSViewer.EPSThumbnail`

### 6.4 Configure App Group capability

For all three targets — host, preview, thumbnail:

1. Signing & Capabilities → + Capability → App Groups
2. Add group: `group.io.github.<username>.EPSViewer`
3. Same group ID across all three targets.

### 6.5 Configure each target's signing

- Team: Personal Team
- Signing Certificate: "Sign to Run Locally" or "Apple Development"
- Hardened Runtime: **No** during development. (Open-source consumers building from source need not enable it. Optional in CI builds.)

### 6.6 Add the shared sources

The `Shared/` directory contains files that compile into all three targets:

1. Drag `Shared/` into Xcode project navigator
2. For each `.swift` file in `Shared/`, ensure all three targets are checked in the Target Membership inspector

This is simpler than a Swift Package for v1; can be migrated to a Swift Package later if the codebase grows.

### 6.7 Run Script Phase to bundle the converter binary

Each of the three targets gets a Run Script Phase **before** "Compile Sources":

```bash
# Copy the universal converter binary into Contents/Tools/
SRC="${SRCROOT}/ghostscript/universal/converter"
DST_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Tools"

if [ ! -f "$SRC" ]; then
    echo "error: converter binary not found at $SRC"
    echo "error: run ghostscript/build-universal.sh first"
    exit 1
fi

mkdir -p "$DST_DIR"
cp -f "$SRC" "$DST_DIR/converter"
chmod +x "$DST_DIR/converter"
```

For the host app, `$WRAPPER_NAME` = `EPSViewer.app`. For each extension, it's `EPSPreview.appex` etc. The same script works for all three thanks to the build variables.

---

## 7. Phase 3 — Shared Renderer Module

The `Shared/` files implement the rendering pipeline used by all three targets.

### 7.1 `Shared/CacheStore.swift`

```swift
import Foundation

/// Manages the App Group shared cache directory.
/// All three targets agree on this path via the App Group identifier.
enum CacheStore {
    static let appGroupID = "group.io.github.<username>.EPSViewer"

    /// Resolved cache directory inside the App Group container.
    /// Returns nil if the App Group entitlement is misconfigured.
    static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }

        let dir = container.appendingPathComponent("EPSViewerCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Lists cached PDF files older than `age` for cache eviction tasks.
    static func evict(olderThan age: TimeInterval) {
        guard let dir = directory else { return }
        let cutoff = Date().addingTimeInterval(-age)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls {
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
```

### 7.2 `Shared/Hashing.swift`

```swift
import Foundation
import CryptoKit

enum Hashing {
    /// SHA-256 over (absolute path, mtime, size). Captures content edits without
    /// hashing the file body — critical for performance on large EPS files.
    static func cacheKey(for url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        let raw = "\(url.path)|\(mtime)|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

### 7.3 `Shared/ProcessRunner.swift`

```swift
import Foundation

enum ProcessError: LocalizedError {
    case nonzeroExit(status: Int32, stderr: String)
    case spawnFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .nonzeroExit(let s, let e):
            return "Converter exited with status \(s): \(e.prefix(500))"
        case .spawnFailed(let e):
            return "Could not launch converter: \(e.localizedDescription)"
        }
    }
}

enum ProcessRunner {
    /// Runs `executable` with `arguments`, blocking until exit. Throws on non-zero exit.
    static func run(executable: URL, arguments: [String]) throws {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments

        let stderrPipe = Pipe()
        p.standardError = stderrPipe
        p.standardOutput = Pipe()    // discard stdout

        do {
            try p.run()
        } catch {
            throw ProcessError.spawnFailed(underlying: error)
        }
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let msg = String(data: data ?? Data(), encoding: .utf8) ?? "unknown"
            throw ProcessError.nonzeroExit(status: p.terminationStatus, stderr: msg)
        }
    }
}
```

### 7.4 `Shared/Renderer.swift`

```swift
import Foundation

/// EPS/PS → PDF renderer with App-Group-shared caching.
/// Singleton actor — used identically by host app and both extensions.
actor Renderer {
    static let shared = Renderer()

    private var inflight: [String: Task<URL, Error>] = [:]

    /// Returns a cached PDF URL for the given EPS/PS file. Renders if necessary.
    func renderPDF(for source: URL) async throws -> URL {
        guard let cacheDir = CacheStore.directory else {
            throw RendererError.cacheUnavailable
        }
        let key = try Hashing.cacheKey(for: source)
        let target = cacheDir.appendingPathComponent("\(key).pdf")

        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        if let existing = inflight[key] { return try await existing.value }

        let task = Task<URL, Error> {
            defer { inflight[key] = nil }
            try renderToPDF(source: source, output: target)
            return target
        }
        inflight[key] = task
        return try await task.value
    }

    /// Synchronous PDF render. Used inside the actor or from background queues.
    private func renderToPDF(source: URL, output: URL) throws {
        let converter = converterURL()
        try ProcessRunner.run(executable: converter, arguments: [
            "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dSAFER",
            "-dEPSCrop",
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-sOutputFile=\(output.path)",
            source.path,
        ])

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw RendererError.outputMissing
        }
    }

    /// One-off PNG render to an arbitrary location — used by Export.
    /// Not cached; caller specifies destination.
    nonisolated func renderPNG(source: URL, output: URL, dpi: Int) throws {
        let converter = converterURL()
        try ProcessRunner.run(executable: converter, arguments: [
            "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dSAFER",
            "-dEPSCrop",
            "-dTextAlphaBits=4", "-dGraphicsAlphaBits=4",
            "-sDEVICE=png16m",
            "-r\(dpi)",
            "-sOutputFile=\(output.path)",
            source.path,
        ])
    }

    /// `Contents/Tools/converter` adjacent to the calling bundle's executable.
    private nonisolated func converterURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Tools/converter")
    }
}

enum RendererError: LocalizedError {
    case cacheUnavailable
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable: return "App Group cache directory is not accessible. Check entitlements."
        case .outputMissing: return "Converter reported success but produced no output file."
        }
    }
}
```

---

## 8. Phase 4 — Quick Look Preview Extension

### 8.1 `EPSPreview/PreviewViewController.swift`

```swift
import Cocoa
import Quartz
import PDFKit

class PreviewViewController: NSViewController, QLPreviewingController {

    private let pdfView: PDFView = {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displayDirection = .vertical
        v.backgroundColor = .clear
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
        root.addSubview(pdfView)
        root.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: root.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.8),
        ])
        self.view = root
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let pdfURL = try await Renderer.shared.renderPDF(for: url)
                let document = PDFDocument(url: pdfURL)
                await MainActor.run {
                    self.pdfView.document = document
                    self.pdfView.isHidden = (document == nil)
                    self.errorLabel.isHidden = true
                    handler(document == nil ? RendererError.outputMissing : nil)
                }
            } catch {
                await MainActor.run {
                    self.pdfView.document = nil
                    self.pdfView.isHidden = true
                    self.errorLabel.stringValue = error.localizedDescription
                    self.errorLabel.isHidden = false
                    handler(nil)
                }
            }
        }
    }
}
```

### 8.2 `EPSPreview/Info.plist`

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
    <string>1.0.0</string>
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

### 8.3 `EPSPreview/EPSPreview.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.io.github.<username>.EPSViewer</string>
    </array>
</dict>
</plist>
```

---

## 9. Phase 5 — Thumbnail Extension

### 9.1 `EPSThumbnail/ThumbnailProvider.swift`

```swift
import QuickLookThumbnailing
import PDFKit
import AppKit

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        Task {
            do {
                let pdfURL = try await Renderer.shared.renderPDF(for: request.fileURL)
                guard let doc = PDFDocument(url: pdfURL),
                      let page = doc.page(at: 0) else {
                    handler(nil, RendererError.outputMissing)
                    return
                }

                let pageRect = page.bounds(for: .mediaBox)
                let scaleX = request.maximumSize.width / pageRect.width
                let scaleY = request.maximumSize.height / pageRect.height
                let scale = min(scaleX, scaleY)
                let outSize = NSSize(
                    width: pageRect.width * scale,
                    height: pageRect.height * scale)

                let reply = QLThumbnailReply(contextSize: outSize) { context in
                    NSGraphicsContext.saveGraphicsState()
                    let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
                    NSGraphicsContext.current = nsCtx
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: context)
                    NSGraphicsContext.restoreGraphicsState()
                    return true
                }
                handler(reply, nil)
            } catch {
                handler(nil, error)
            }
        }
    }
}
```

### 9.2 `EPSThumbnail/Info.plist`

Same structure as preview, but with extension point identifier `com.apple.quicklook.thumbnail` and principal class `ThumbnailProvider`. The `QLSupportedContentTypes` array is identical.

### 9.3 `EPSThumbnail/EPSThumbnail.entitlements`

Identical to `EPSPreview.entitlements` — same App Group.

---

## 10. Phase 6 — Host App Implementation

The host app provides three differentiating features beyond what Anybox offers: a **dedicated viewer window**, **zoom/pan**, and **PNG/PDF export**.

### 10.1 `EPSViewer/EPSViewerApp.swift`

```swift
import SwiftUI

@main
struct EPSViewerApp: App {
    @StateObject private var openController = DocumentOpener()

    var body: some Scene {
        WindowGroup(id: "viewer", for: URL.self) { $url in
            ViewerWindow(url: url)
                .onAppear {
                    if url == nil { openController.showOpenPanel() }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openController.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export as PDF…") { openController.exportPDF() }
                Button("Export as PNG…") { openController.exportPNG() }
            }
        }
    }
}
```

### 10.2 `EPSViewer/DocumentOpener.swift`

```swift
import AppKit
import SwiftUI

@MainActor
class DocumentOpener: ObservableObject {
    @Published var currentURL: URL?

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epsImage, .postscript]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        currentURL = url
        // Tell SwiftUI to open a window for this URL
        NSWorkspace.shared.open(url)  // this triggers our scene to receive it
    }

    func exportPDF() {
        guard let source = currentURL else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".pdf"
        guard savePanel.runModal() == .OK, let dest = savePanel.url else { return }

        Task {
            do {
                let cached = try await Renderer.shared.renderPDF(for: source)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: cached, to: dest)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func exportPNG() {
        guard let source = currentURL else { return }
        let dpi = ExportPanel.runForPNG()    // see §10.4
        guard dpi > 0 else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".png"
        guard savePanel.runModal() == .OK, let dest = savePanel.url else { return }

        Task.detached {
            do {
                try Renderer.shared.renderPNG(source: source, output: dest, dpi: dpi)
            } catch {
                await MainActor.run { NSAlert(error: error).runModal() }
            }
        }
    }
}

import UniformTypeIdentifiers
extension UTType {
    static let epsImage = UTType("com.adobe.encapsulated-postscript")!
    static let postscript = UTType("com.adobe.postscript")!
}
```

### 10.3 `EPSViewer/ViewerWindow.swift`

```swift
import SwiftUI
import PDFKit
import AppKit

struct ViewerWindow: View {
    let url: URL?
    @State private var pdfDocument: PDFDocument?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let doc = pdfDocument {
                PDFKitView(document: doc)
            } else if let msg = errorMessage {
                Text(msg).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(url?.lastPathComponent ?? "EPS Viewer")
        .toolbar { ViewerToolbar(document: $pdfDocument) }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        do {
            let pdfURL = try await Renderer.shared.renderPDF(for: url)
            await MainActor.run {
                pdfDocument = PDFDocument(url: pdfURL)
                errorMessage = pdfDocument == nil ? "Failed to load PDF." : nil
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
```

### 10.4 `EPSViewer/ViewerToolbar.swift` (zoom controls + Export buttons)

```swift
import SwiftUI
import PDFKit

struct ViewerToolbar: ToolbarContent {
    @Binding var document: PDFDocument?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { zoom(out: false) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
            Button { zoom(out: true) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { fitToWindow() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Fit to window")
        }
    }

    private func zoom(out: Bool) {
        guard let pdfView = currentPDFView() else { return }
        if out { pdfView.scaleFactor /= 1.25 }
        else   { pdfView.scaleFactor *= 1.25 }
    }

    private func fitToWindow() {
        guard let pdfView = currentPDFView() else { return }
        pdfView.autoScales = true
    }

    private func currentPDFView() -> PDFView? {
        // Walk the responder chain or keep a reference. Simplified for brevity;
        // production code should use a coordinator pattern via NSViewRepresentable.
        NSApp.keyWindow?.contentView?.subviews(ofType: PDFView.self).first
    }
}

extension NSView {
    func subviews<T: NSView>(ofType: T.Type) -> [T] {
        var result: [T] = []
        for sub in subviews {
            if let t = sub as? T { result.append(t) }
            result.append(contentsOf: sub.subviews(ofType: T.self))
        }
        return result
    }
}
```

### 10.5 `EPSViewer/ExportPanel.swift` (DPI selector for PNG export)

```swift
import AppKit

enum ExportPanel {
    /// Modal DPI picker; returns chosen DPI or 0 if cancelled.
    static func runForPNG() -> Int {
        let alert = NSAlert()
        alert.messageText = "Export as PNG"
        alert.informativeText = "Select export resolution."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        popup.addItems(withTitles: ["72 DPI (screen)", "150 DPI (web)", "300 DPI (print)", "600 DPI (high)"])
        popup.selectItem(at: 2)
        alert.accessoryView = popup

        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return 0 }

        switch popup.indexOfSelectedItem {
        case 0: return 72
        case 1: return 150
        case 2: return 300
        case 3: return 600
        default: return 300
        }
    }
}
```

### 10.6 `EPSViewer/Info.plist` (file handler registration)

The host app's Info.plist must declare itself as a handler for `.eps` and `.ps`:

```xml
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
```

`LSHandlerRank=Alternate` lets users keep TeXShop or another app as their primary handler if they prefer; EPS Viewer just registers itself as an option in "Open With…". Set to `Default` if you want EPS Viewer to be the default opener.

### 10.7 `EPSViewer/EPSViewer.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.io.github.<username>.EPSViewer</string>
    </array>
</dict>
</plist>
```

Note `read-write` (not just `read-only`) because the host app needs to write export files chosen by the user.

---

## 11. Phase 7 — Build, Sign Locally, Test

### 11.1 Build all three targets

```bash
xcodebuild -project EPSViewer.xcodeproj \
    -scheme EPSViewer \
    -configuration Release \
    -derivedDataPath build/ \
    build
```

Output: `build/Build/Products/Release/EPSViewer.app` with both extensions embedded under `Contents/PlugIns/`.

### 11.2 `scripts/verify-bundle.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSViewer.app}"

echo "── Bundle structure ──"
ls -la "$APP/Contents/Tools/"
ls -la "$APP/Contents/PlugIns/"
ls -la "$APP/Contents/PlugIns/EPSPreview.appex/Contents/Tools/"
ls -la "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Tools/"

echo "── Converter binaries ──"
file "$APP/Contents/Tools/converter"
file "$APP/Contents/PlugIns/EPSPreview.appex/Contents/Tools/converter"
file "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Tools/converter"

echo "── Codesign status ──"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier"
```

### 11.3 `scripts/adhoc-sign.sh` (for distributing without Apple Developer Program)

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Build/Products/Release/EPSViewer.app}"

# Ad-hoc signing: --sign "-"  means "no real identity, just compute the hash"
# This is what GitHub Actions and most open-source macOS projects use.

# Helper binaries first (innermost out):
codesign --force --sign "-" "$APP/Contents/Tools/converter"
codesign --force --sign "-" "$APP/Contents/PlugIns/EPSPreview.appex/Contents/Tools/converter"
codesign --force --sign "-" "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Tools/converter"

# Extensions:
codesign --force --sign "-" --entitlements EPSPreview/EPSPreview.entitlements \
    "$APP/Contents/PlugIns/EPSPreview.appex"
codesign --force --sign "-" --entitlements EPSThumbnail/EPSThumbnail.entitlements \
    "$APP/Contents/PlugIns/EPSThumbnail.appex"

# Host app last:
codesign --force --sign "-" --entitlements EPSViewer/EPSViewer.entitlements "$APP"

# Verify the signature graph
codesign --verify --deep --strict --verbose=2 "$APP"
```

Ad-hoc signed apps will show a Gatekeeper warning on first launch, but users can override it via right-click → Open. This is the standard open-source distribution path on macOS.

### 11.4 Install and register

```bash
cp -R "$APP" /Applications/
open /Applications/EPSViewer.app
killall Finder

# Confirm both extensions registered
pluginkit -m -p com.apple.quicklook.preview | grep -i EPSViewer
pluginkit -m -p com.apple.quicklook.thumbnail | grep -i EPSViewer
```

### 11.5 Functional checklist

- [ ] Spacebar on `.eps` in Finder shows preview within 250 ms (cold)
- [ ] Arrow-key navigation through 10 EPS files; second pass is instant
- [ ] Finder folder view shows actual graph thumbnails (may take a moment to populate)
- [ ] Double-click `.eps` opens host viewer window
- [ ] Toolbar zoom in/out buttons work; "Fit to window" resets
- [ ] File → Export as PDF → produces a valid PDF identical to the cached preview
- [ ] File → Export as PNG → DPI selector appears; chosen DPI is honored in output
- [ ] Drag a .eps file onto the EPSViewer dock icon — opens in viewer
- [ ] Cache directory at `~/Library/Group Containers/group.io.github.<username>.EPSViewer/EPSViewerCache/` contains PDFs
- [ ] Render the same file in Quick Look and host window — only one cache entry exists (App Group sharing works)

---

## 12. Open Source Repository Setup

### 12.1 `README.md` essentials

The README should answer four questions in the first screen:

1. **What does it do?** — restore Finder Quick Look and add a viewer for `.eps`/`.ps` after Apple removed support
2. **Who is it for?** — academics, designers, anyone who still uses EPS
3. **How do I install?** — download the latest release, drag to Applications, run once
4. **Why open source?** — Ghostscript bundling requires AGPL; transparency benefits scientific users

Include screenshots of: Finder thumbnails, Quick Look preview, viewer window with toolbar, export dialog.

### 12.2 `LICENSE`

Copy the full AGPL-3.0 text from https://www.gnu.org/licenses/agpl-3.0.txt as `LICENSE` at the repo root.

### 12.3 `NOTICE.md`

```markdown
# Third-party software

This project incorporates **Ghostscript** (https://www.ghostscript.com/),
licensed under AGPL-3.0. The bundled `converter` binary in each `Contents/Tools/`
directory is a statically-linked build of Ghostscript with the configuration
specified in `ghostscript/build-*.sh`.

The Ghostscript source code corresponding to the binary in this release is
available in the `ghostscript/` directory of the source repository, and a
reference to the upstream release is maintained in `ghostscript/README.md`.
```

### 12.4 `docs/building-from-source.md`

Step-by-step guide for users who want to verify and build the binary themselves rather than trusting the release artifact. This is the AGPL spirit: users should be able to reproduce.

```markdown
# Building EPS Viewer from source

## Requirements
- macOS 14.0+
- Xcode 16.0+
- ~30 minutes (mostly waiting for Ghostscript to compile)

## Steps

1. Clone:
   git clone https://github.com/<username>/eps-viewer
   cd eps-viewer

2. Build Ghostscript (one-time):
   cd ghostscript
   bash build-universal.sh
   cd ..

3. Open in Xcode:
   open EPSViewer.xcodeproj

4. Sign in with any Apple ID under Xcode Settings → Accounts (free).
   In project settings, select your Personal Team for all three targets.

5. Build & run (⌘R). The first run installs the extensions; you may need
   to enable them in System Settings → Privacy & Security → Extensions.
```

### 12.5 `.github/workflows/build.yml` (CI)

```yaml
name: Build
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Cache Ghostscript build
        id: gs-cache
        uses: actions/cache@v4
        with:
          path: ghostscript/universal
          key: gs-universal-${{ hashFiles('ghostscript/build-*.sh') }}-v1

      - name: Build Ghostscript
        if: steps.gs-cache.outputs.cache-hit != 'true'
        run: |
          cd ghostscript
          bash build-universal.sh

      - name: Build app
        run: |
          xcodebuild -project EPSViewer.xcodeproj \
            -scheme EPSViewer \
            -configuration Release \
            -derivedDataPath build/ \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            build

      - name: Ad-hoc sign
        run: bash scripts/adhoc-sign.sh build/Build/Products/Release/EPSViewer.app

      - name: Package DMG
        run: bash scripts/package-dmg.sh

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: EPSViewer-${{ github.sha }}.dmg
          path: build/EPSViewer-*.dmg
```

### 12.6 Release artifact strategy

Three options for users, in increasing trust required:

1. **Build from source** — users follow `docs/building-from-source.md`. Maximum trust, ~30 min of compile time.
2. **Download CI build** — every push to `main` produces an ad-hoc signed `.dmg` in GitHub Actions artifacts. Users override Gatekeeper once.
3. **Tagged Release** — tagged versions get a manually-curated release entry with changelog, screenshots, and the same ad-hoc signed `.dmg`.

We don't promise notarized builds in v1. If contributor demand grows and someone donates a Developer ID, that path can be added later in CI without changing the architecture.

### 12.7 First-run instructions for Gatekeeper-blocked downloads

Add to the GitHub Release notes:

```
First launch (one-time):
1. Drag EPSViewer.app to /Applications.
2. Right-click EPSViewer.app → Open → Open in the dialog.
3. macOS remembers your choice; subsequent launches work normally.

Or, from terminal:
  xattr -dr com.apple.quarantine /Applications/EPSViewer.app
```

---

## 13. Optional: Sparkle for in-app updates

Anybox uses Sparkle 2.x to deliver updates without reinstalling. For an open-source project this is a polish item; v1.0 doesn't need it. To add later:

1. Add Sparkle as Swift Package: `https://github.com/sparkle-project/Sparkle`
2. Generate a key pair (`generate_keys` in Sparkle distribution)
3. Add `SUFeedURL` to host app's Info.plist pointing to a GitHub-Pages-hosted appcast.xml
4. Sign each release's appcast entry with the private key

Without notarization, users still see the Gatekeeper prompt on the first run of an updated version, but the update download itself works fine.

---

## 14. Troubleshooting

### Quick Look extension doesn't appear

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain system -domain user
killall Finder
```

Then re-open the host app once. Confirm via System Settings → Privacy & Security → Extensions → Quick Look.

### App Group cache directory is nil

The container URL is nil if the App Group entitlement isn't applied. Verify:

```bash
codesign -d --entitlements - "$APP" | grep -A2 "application-groups"
```

All three targets must show the same group identifier.

### Converter exits with `/invalidfileaccess`

The converter binary couldn't read the input file under sandbox. The URL passed to extension methods (`preparePreviewOfFile`, `provideThumbnail`) is granted automatically; if you see this, you may be passing the wrong URL. For the host app, ensure files come via `NSOpenPanel` or document opening (which grants security-scoped access).

### "App is damaged and can't be opened"

This is Gatekeeper rejecting an ad-hoc signed download. Either right-click → Open or run:

```bash
xattr -dr com.apple.quarantine /Applications/EPSViewer.app
```

### Personal Team signing certificate keeps expiring

Personal Team certificates have shorter lifetimes than Developer ID certificates. Re-build in Xcode when needed. CI builds from GitHub Actions don't have this issue because they ad-hoc sign.

---

## 15. Effort Breakdown

| Phase | Task | Days |
|-------|------|------|
| 0 | PoC sandbox/exec validation (gs in extension bundle) | 0.5 |
| 1 | Ghostscript static universal build | 0.5 |
| 2 | Xcode project, three targets, App Group | 0.5 |
| 3 | Shared module (Renderer, CacheStore, Hashing, ProcessRunner) | 1 |
| 4 | Quick Look Preview Extension | 0.5 |
| 5 | Thumbnail Extension | 0.5 |
| 6 | Host app: viewer window, toolbar, file open, export | 1.5 |
| 7 | Local build, ad-hoc sign, smoke test | 0.5 |
| 8 | GitHub repo setup: README, LICENSE, NOTICE, CI, docs | 1 |
| **Total** | | **~6 days** |

A second iteration polishing edge cases, fixing real-world EPS quirks, and tuning performance: another 1–2 days.

---

## 16. Future Enhancements

- Multi-page PostScript navigation (page selector toolbar)
- Configurable cache size limits with LRU eviction
- Background pre-warm on folder open: when host app opens a directory, render all sibling EPS in parallel
- Sparkle-based in-app updates (§13)
- Localizations (Korean, Japanese, German, etc.)
- Donated Developer ID for signed/notarized builds (community contribution)
- SVG export
- Batch export ("Export entire folder as PDFs")
- Drag-out from Quick Look preview to copy as PNG/PDF (advanced QL feature)

---

## Appendix A — Quick reference

```
Bundle IDs:
  Host:       io.github.<username>.EPSViewer
  Preview:    io.github.<username>.EPSViewer.EPSPreview
  Thumbnail:  io.github.<username>.EPSViewer.EPSThumbnail
  App Group:  group.io.github.<username>.EPSViewer

UTIs handled:
  com.adobe.encapsulated-postscript    (.eps)
  com.adobe.postscript                  (.ps)

Converter location (per-bundle):
  Contents/Tools/converter

Render pipeline:
  EPS/PS → converter (gs) → PDF → PDFKit
                              ↓ (export PNG only)
                              converter (gs) re-render at chosen DPI

Cache location:
  ~/Library/Group Containers/<group-id>/EPSViewerCache/<sha256>.pdf

Cache key:
  sha256("<absolute-path>|<mtime>|<size>")

Performance contract:
  cold render p50      ≤ 250 ms
  warm Quick Look p50  ≤ 30 ms
  PNG export 300 DPI   ≤ 500 ms
  extension RSS        ≤ 50 MB
```

## Appendix B — Differences from Anybox EPS Preview

| Feature | Anybox EPS Preview | EPS Viewer |
|---------|-------------------|-----------|
| Quick Look preview | ✓ | ✓ |
| Finder thumbnails | ✓ | ✓ |
| Viewer window with zoom | ✗ | ✓ |
| Export to PNG | ✗ | ✓ (configurable DPI) |
| Export to PDF | ✗ | ✓ |
| Auto-update | ✓ (Sparkle) | optional v1.1 |
| Code signing | Developer ID + notarized | Ad-hoc (or community Developer ID) |
| Distribution | Direct download, $6.99 | GitHub, free |
| License | proprietary | AGPL-3.0 |
| Source available | no | yes |
| Build reproducibility | not applicable | full (AGPL requirement) |

The two projects are complementary in spirit. Anybox is a polished commercial product for users who want spacebar preview without thinking. EPS Viewer is for users who additionally want to open, zoom, export, audit the source, or fork the project — i.e. the academic and open-source community.

## Appendix C — End-User Runtime Dependencies

The shipped `.dmg` requires only:

- macOS 14.0 (Sonoma) or later

End users do **not** need: TeX Live, TeXShop, MacTeX, Homebrew, Ghostscript, Rosetta 2, Xcode, Python, or any other tool. Everything required is inside the app bundle.
