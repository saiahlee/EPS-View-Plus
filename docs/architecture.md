# Architecture

## Component diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  EPSViewer.app    (host bundle, ~18 MB)                             │
│                                                                     │
│  Contents/MacOS/EPSViewer                                           │
│    SwiftUI + AppKit host                                            │
│    • Viewer window (PDFView, zoom, pan)                             │
│    • File-open handler (UTI-registered for .eps / .ps)              │
│    • Export menu (PNG / PDF)                                        │
│    • Drag-drop receiver                                             │
│                                                                     │
│  Contents/Tools/converter                                           │
│    Statically-linked Ghostscript universal binary                   │
│                                                                     │
│  Contents/PlugIns/EPSPreview.appex                                  │
│    Quick Look preview extension (QLPreviewingController)            │
│      + its own copy of Contents/Tools/converter                     │
│                                                                     │
│  Contents/PlugIns/EPSThumbnail.appex                                │
│    Quick Look thumbnail extension (QLThumbnailProvider)             │
│      + its own copy of Contents/Tools/converter                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Shared App Group container                                         │
│  ~/Library/Group Containers/group.io.github.saiahlee.EPSViewer/     │
│      EPSViewerCache/<sha256(path|mtime|size)>.pdf                   │
│                                                                     │
│  Read/written by all three targets above. A file rendered when      │
│  opened in the host window is instantly available to Finder         │
│  spacebar Quick Look — and vice versa.                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Render pipeline

```
EPS/PS  →  converter (gs, pdfwrite)  →  PDF  →  PDFKit
                                          ↓ (PNG export only)
                                      converter (gs, png16m) at chosen DPI
```

PDF is the canonical render output. A single artifact serves four use cases:

1. **Quick Look display** — `PDFView` renders cached PDF with zoom-in-Quick-Look "for free".
2. **Thumbnail generation** — `QLThumbnailProvider` rasterizes the first page of the PDF to a CGContext.
3. **Host window viewer** — same `PDFView`, just in a larger window with a toolbar.
4. **Export PDF** — direct file copy from cache to the user's chosen location.

PNG export is its own gs invocation at the user's chosen DPI, since re-rasterizing a low-DPI PNG up loses quality. The PDF cache isn't reused for PNG.

## Cache key

```
sha256("<absolute-path>|<mtime>|<size>")
```

Encoded as lowercase hex. Same algorithm in the macOS and Windows versions.

## Why three copies of the converter?

Each `.appex` extension and the host app run in their own sandbox. The sandbox permits exec of binaries inside the calling bundle but not arbitrary cross-bundle exec. So each target carries its own copy of `Contents/Tools/converter`. This costs ~36 MB total (3 × ~12 MB) but eliminates an entire class of sandbox-exec headaches.

An XPC-service-based design could share one `gs`, but that's significant additional complexity for one-time disk savings.

## Why an App Group?

Without it, each of the three targets has its own private cache. A file previewed via spacebar wouldn't help when later opened in the host window. With an App Group:

- One render serves all three targets forever (until the file's mtime changes)
- Opening a folder in the host app effectively pre-warms Finder's Quick Look for that folder
- Cache eviction is centralized

App Groups don't require Apple Developer Program for local development — Personal Team accounts can create them for ad-hoc-signed builds.

## Performance contract

| Scenario | Target |
|----------|--------|
| Cold render (first preview of a file) | ≤ 250 ms p50, ≤ 500 ms p95 |
| Warm Quick Look (PDF cached) | ≤ 30 ms |
| Extension launch (first spacebar of session) | ≤ 200 ms |
| Memory in extension | ≤ 50 MB resident |
| Host window cold open | ≤ 500 ms |
| Export PNG (300 DPI, average graph) | ≤ 500 ms |

The cache hit rate is the main lever. Once a file has been viewed in any target, all other views are warm thanks to the App Group shared cache.
