# Ghostscript build

This directory produces `universal/converter` — the gs binary that gets
copied into each app/extension's `Contents/Tools/`.

There are **two strategies**, picked by environment variable:

| Strategy | When | Trade-off |
|----------|------|-----------|
| **Bundle Homebrew gs (default)** | Anyone on a recent macOS with Homebrew | Reliable, fast (~10 s if gs already installed). Single-arch only — host's. Pulls in a few dylibs. |
| **Build from source** (`EPS_GS_BUILD_FROM_SOURCE=1`) | AGPL-purist contributors who want a fully reproducible bytes-from-source binary | ~25 min. Universal arm64+x86_64. Currently fails on macOS Command Line Tools 17+/clang 21 due to upstream zlib + C23 incompatibility — patches required. |

Most contributors should let `bash build-universal.sh` do the default
brew-bundle path. The source path remains for AGPL-conscientious users
who need every byte traceable to source.

## Pinned version

```
GS_VERSION=10.04.0
upstream:  https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/tag/gs10040
SHA256:    7ec0eee2e5cf72a82c0a16c2af9b78c708c4d1f5c1baf2d0c1f8b3eb3a05e9d5
           (verify against the value published by Artifex on the upstream release page)
```

## Build (default: bundle from Homebrew, ~10 seconds)

Requires Homebrew (https://brew.sh). The script will install the
`ghostscript` formula automatically if not already present.

```bash
bash build-universal.sh
```

Produces:
- `universal/converter` — the gs executable
- `universal/lib/*.dylib` — its non-system dependencies, with
  install_name_tool rewrites so they're found via `@rpath`

Total bundle size: ~25–35 MB depending on Homebrew gs's current
dependency set.

## Build from source (AGPL-purist, ~25 minutes)

```bash
EPS_GS_BUILD_FROM_SOURCE=1 bash build-universal.sh
```

This compiles Ghostscript from the upstream tarball into a static
universal binary with no external dylibs. **Note**: as of macOS Command
Line Tools 17 (clang 21, default C standard C23), the upstream
`ghostscript-10.04.0` source tree's bundled zlib does not compile
without patches because of K&R-style declarations and `fdopen` macro
shadowing. We've left the build scripts as-is so contributors can apply
the appropriate upstream/Artifex patches as those land. In the meantime
the brew-bundle path is the supported route.

## Verification

After running `bash build-universal.sh`:

```bash
file universal/converter
otool -L universal/converter
universal/converter --version
```

Brew-bundle path: `otool -L` shows the converter linked against
`@rpath/<dylib>` for each library copied into `universal/lib/`.

From-source path (when the upstream incompatibility is patched):
`otool -L` should show only system libs (`/usr/lib/libSystem.B.dylib`
etc.) and `lipo -info` should report two architectures.

## Re-running after a partial / failed build

```bash
cd ghostscript
rm -rf src install-arm64 install-x86_64 universal
bash build-universal.sh
```

`fetch-source.sh` is idempotent: it skips re-downloading the tarball
if the archive is already there.

## Known issue: clang 21 / C23 vs. bundled zlib (from-source path only)

Recent macOS Command Line Tools ship clang 21, which defaults to C23.
Ghostscript 10.04.0's bundled zlib uses K&R-style function declarations
and a `#define fdopen(fd,mode) NULL` macro that conflicts with the
SDK's `fdopen` declaration under C23:

```
./_stdio.h:322:7: error: expected identifier or '('
./zlib/zutil.h:147:33: note: expanded from macro 'fdopen'
make: *** [obj/zutil.o] Error 1
```

`build-arm64.sh` / `build-x86_64.sh` already pass `-std=gnu17` in
CFLAGS, which is necessary but not sufficient — clang 21 still hits
the `fdopen` macro shadow because the bug is in zlib's internal logic,
not just in the language standard. A cleaner long-term fix is to apply
upstream's patched zlib (or use `--with-system-zlib`); we have not yet
prototyped this. Until then the **brew-bundle path is the supported
route** for everyday building.

## Devices/drivers we enable

The minimum required for the app's two output formats:

- `pdfwrite` — for the canonical PDF render that feeds Quick Look, the
  thumbnail provider, and PDF export
- `png16m` — for PNG export at user-selected DPI
- `bbox` — for bounding-box queries (used by EPSCrop)
- `jpeg` — for embedded JPEG-in-EPS support

Everything else (`cups`, `dbus`, `gtk`, `fontconfig`, `x11`, `tesseract`,
`libidn`, `libpaper`) is disabled to minimize binary size and to remove
runtime/system dependencies.
