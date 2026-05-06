# EPS Viewer for macOS

> Restore Quick Look preview, Finder thumbnails, and a dedicated viewer for `.eps` and `.ps` files — features Apple removed from Preview starting with macOS Ventura.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)]()

## What it does

- **Spacebar Quick Look** in Finder — fly through a folder of EPS files with arrow keys
- **Finder thumbnails** — actual graph previews instead of generic icons
- **Dedicated viewer window** — double-click `.eps` / `.ps` to open with zoom and pan
- **Export** to PNG (configurable DPI) or PDF

Self-contained: bundles a statically-linked Ghostscript universal binary. No TeX Live, no Homebrew, no Rosetta required.

## Who it's for

Academics, designers, and anyone who still works with EPS files on modern macOS — and prefers free, open, auditable software.

## Install

Three options, in increasing trust required:

1. **Build from source** — see [docs/building-from-source.md](docs/building-from-source.md). Maximum trust, ~30 minutes of compile time.
2. **Download a tagged release** — grab `EPSViewer-x.y.z.dmg` from [Releases](https://github.com/saiahlee/EPS-View-Plus/releases), drag to `/Applications`.
3. **Download a CI build** — every push to `main` produces an unsigned `.dmg` artifact in [GitHub Actions](https://github.com/saiahlee/EPS-View-Plus/actions).

### First launch (one-time)

The `.dmg` is ad-hoc signed (no Apple Developer Program), so Gatekeeper will block it on first launch:

```bash
# Either right-click EPSViewer.app → Open → Open in dialog
# Or strip the quarantine attribute:
xattr -dr com.apple.quarantine /Applications/EPSViewer.app
```

After the first launch, macOS remembers your decision.

## Why open source

Bundling Ghostscript means inheriting AGPL-3.0. We chose to make this an asset rather than a constraint: the source is auditable, the binary is reproducible, and academic users can verify their toolchain.

## Architecture at a glance

```
EPSViewer.app
├── EPSViewer (host app — viewer window, zoom, export)
├── EPSPreview.appex (Quick Look preview)
├── EPSThumbnail.appex (Finder thumbnails)
└── Tools/converter (statically-linked Ghostscript)
```

All three targets share a render cache under
`~/Library/Group Containers/group.io.github.saiahlee.EPSViewer/EPSViewerCache/`.

A file rendered once via Quick Look is instantly available in the viewer window, and vice versa.

See [docs/architecture.md](docs/architecture.md) for details.

## License & attributions

EPS Viewer is licensed under [AGPL-3.0](LICENSE).

Bundled third-party software:
- [Ghostscript](https://www.ghostscript.com/) (AGPL-3.0)

See [NOTICE.md](NOTICE.md) for full attributions.

## Companion project

A Windows version of EPS Viewer with the same feature set is available at [eps-viewer-win](https://github.com/saiahlee/EPS-View-Plus-Windows).
