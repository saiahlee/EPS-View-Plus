# Design decisions

A short log of the non-obvious choices we made and the alternatives we
weighed. New contributors should read this before proposing architectural
changes.

## Why PDF as the cached render output (not PNG)

A single PDF artifact serves four use cases for free:

1. Quick Look preview (PDFView decodes in milliseconds, zoom is vector)
2. Thumbnail generation (rasterize first page)
3. Host viewer window (same PDFView, larger window)
4. PDF export (copy file from cache)

PNG would be ~30% faster to render cold, but we'd then re-render at every
zoom step in Quick Look and lose the "PDF export = free" property.

## Why we ship Ghostscript as a binary instead of asking users to `brew install`

Sci/engineering users frequently don't have Homebrew. A "self-contained"
deliverable that just works is more important than the disk savings of
asking users to bring their own gs.

## Why ad-hoc signing instead of Apple Developer ID

- Developer ID requires a $99/year Apple Developer Program membership.
- AGPL distribution is incompatible with App Store anyway.
- The first-launch friction (right-click → Open) is a one-time cost that
  most macOS-savvy users already know.
- A community-donated Developer ID can be wired into CI later without any
  architectural change.

## Why three copies of the converter binary instead of an XPC helper

Sandboxing makes cross-bundle exec hard. The three-copy pattern is what
Anybox EPS Preview ships and is the path of least resistance. ~36 MB total
disk cost is acceptable for the simplicity win.

If this becomes painful (e.g., if we add more bundled tools), an XPC
service is the natural escape hatch.

## Why a shared App Group container

So that a render done by one target (e.g., a Quick Look spacebar preview)
is instantly usable by the others (e.g., the host viewer window). Without
it, opening a file in the host app would re-render even though Finder
already cached it.

## Why we keep `EPSCrop` on by default

Most EPS files in academic / scientific use are graphs or figures with a
tight `BoundingBox` and lots of whitespace outside it. `-dEPSCrop` honors
that bounding box so the rendered output isn't a tiny graph centered on a
huge blank page.

## Why we don't render multi-page PostScript in v1

The 80% case is single-page EPS figures. Multi-page support adds a UI
surface (page selector toolbar), additional edge cases in the cache key
(do we cache per-page?), and risks complicating the Quick Look fast-path.
Future enhancement once v1 is in users' hands.

## Why XcodeGen instead of committing the .xcodeproj

`.xcodeproj/project.pbxproj` files are notoriously hostile to code review:
~hundreds of lines of UUID-keyed XML for what's conceptually a small change.
A `project.yml` is human-readable, diffable, and lets PRs to the build
graph be reviewed sensibly.

## Why no telemetry, no auto-update in v1

- Telemetry: this app sees scientific work product. The trust cost of any
  network traffic outweighs the engineering value.
- Auto-update: Sparkle is great but adds infrastructure (appcast hosting,
  signing keys). Out of scope for v1.0; documented as a future enhancement.
