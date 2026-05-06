# Contributing to EPS Viewer

Thanks for considering a contribution. This project is small and reviews are usually quick.

## Ground rules

1. **AGPL-3.0**. By contributing you agree your changes are licensed under AGPL-3.0.
2. **No proprietary dependencies.** Anything bundled must be redistributable under AGPL or a compatible license. Static linking changes are particularly sensitive — open an issue first.
3. **Reproducible builds.** Anything we ship must be buildable from `main` by following `docs/building-from-source.md`. Don't add steps that require commercial tools or paid accounts.
4. **No telemetry.** This app sees scientific work product. It must not phone home.

## Development setup

1. Build the bundled Ghostscript once: `cd ghostscript && bash build-universal.sh`
2. Generate the Xcode project from `project.yml`: `xcodegen generate` (install with `brew install xcodegen`)
3. Open `EPSViewer.xcodeproj` in Xcode 16+
4. Sign in with any Apple ID under Xcode → Settings → Accounts (free Personal Team account is enough)
5. Build & Run (⌘R)

## Code style

- Swift formatted with `swift-format` (default Apple settings)
- Files end with a single newline
- Public APIs documented with `///` doc comments

## Pull request checklist

- [ ] `xcodebuild -scheme EPSViewer build` succeeds
- [ ] `scripts/verify-bundle.sh build/Build/Products/Release/EPSViewer.app` passes
- [ ] If you changed the renderer or cache, you've manually verified an EPS still previews via Spacebar
- [ ] If you changed the gs invocation, you've documented why in the commit message

## Reporting bugs

A good bug report includes:
- macOS version (Apple → About This Mac)
- EPS Viewer version
- A small `.eps` file that reproduces the bug, if possible
- Output of `Console.app` filtered for `EPSViewer` while the bug occurs
