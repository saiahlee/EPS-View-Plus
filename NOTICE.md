# Third-party software

EPS Viewer for macOS bundles the following third-party software:

## Ghostscript

- **Project**: https://www.ghostscript.com/
- **Source**: https://github.com/ArtifexSoftware/ghostpdl-downloads
- **License**: GNU Affero General Public License v3.0
- **Used as**: `Contents/Tools/converter` in each bundled target (host app, Quick Look extension, Thumbnail extension)

The bundled `converter` binary is a statically-linked Ghostscript build produced by the build scripts in `ghostscript/` of this repository. End-users may reproduce the binary from source by running `ghostscript/build-universal.sh`.

The Ghostscript version pinned for the current release is recorded in `ghostscript/README.md`.

## License obligations

Because Ghostscript is licensed under AGPL-3.0, EPS Viewer is also licensed under AGPL-3.0 (see `LICENSE`). This means:

1. Source code corresponding to every released binary is publicly available in this repository.
2. Modifications of EPS Viewer that are distributed (including served over a network) must be made available under AGPL-3.0.
3. Users have the right to inspect, modify, and rebuild the software from source.

The full text of the AGPL-3.0 license is included in `LICENSE`.
