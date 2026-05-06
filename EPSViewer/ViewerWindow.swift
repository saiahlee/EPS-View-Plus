import AppKit
import PDFKit
import SwiftUI

/// One window per open document.
///
/// Composes the loading state from `DocumentModel` with the PDF view and a
/// minimalist toolbar. The toolbar's zoom and export actions are wired
/// through `pdfCoordinator` and `ExportCoordinator`.
struct ViewerWindow: View {

    @StateObject private var model = DocumentModel()
    @State private var pdfCoordinator: PDFViewRepresentable.Coordinator?

    let initialURL: URL?

    var body: some View {
        Group {
            switch model.state {
            case .empty:
                EmptyStateView()

            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(_, let document):
                PDFViewRepresentable(document: document, coordinator: $pdfCoordinator)

            case .failed(_, let error):
                ErrorStateView(error: error)
            }
        }
        .frame(
            minWidth: 320, maxWidth: .infinity,
            minHeight: 240, maxHeight: .infinity)
        .navigationTitle(model.sourceURL?.lastPathComponent ?? "EPS View+")
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .task(id: initialURL) {
            if let url = initialURL { model.load(url: url) }
        }
        .onChange(of: model.sourceURL) { _, newURL in
            // Reflect the loaded EPS's name in the AppKit window title
            // (NSHostingController doesn't propagate navigationTitle to
            // the parent NSWindow).
            updateHostWindowTitle(to: newURL?.lastPathComponent ?? "EPS View+")
        }
    }

    private func updateHostWindowTitle(to title: String) {
        // Find the NSWindow that hosts this SwiftUI content. We can't
        // hold a reference (View structs are value types), so look it
        // up by the host's content view at update time.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.contentViewController is NSHostingController<ViewerWindow> {
                window.title = title
            }
        }
    }

    // MARK: - Drag & drop helpers
    //
    // We deliberately use the lower-level `loadDataRepresentation` API
    // for `public.file-url` rather than `loadObject(ofClass: URL.self)`.
    // `URL` does not conform to `NSItemProviderReading`, so the latter
    // would fail at runtime even though it compiles cleanly.

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                openPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open EPS or PostScript file (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                pdfCoordinator?.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out (⌘−)")
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.document == nil)

            Button {
                pdfCoordinator?.fitToWindow()
            } label: {
                Label("Fit to Window", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit to window (⌘0)")
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model.document == nil)

            Button {
                pdfCoordinator?.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in (⌘+)")
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.document == nil)

            Spacer()

            Menu {
                Button("Export as PDF…") { exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button("Export as PNG…") { exportPNG() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export to PDF or PNG")
            .disabled(model.sourceURL == nil)
        }
    }

    // MARK: - Actions

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epsImage, .postscript]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an EPS or PostScript file."
        if panel.runModal() == .OK, let url = panel.url {
            model.load(url: url)
        }
    }

    private func exportPDF() {
        guard let source = model.sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".pdf"
        panel.message = "Choose a destination for the exported PDF."
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        Task {
            do {
                try await Renderer.shared.exportPDF(from: source, to: dest)
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func exportPNG() {
        guard let source = model.sourceURL else { return }
        let dpi = ExportPanel.runForPNG()
        guard dpi > 0 else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".png"
        panel.message = "Choose a destination for the exported PNG."
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        Task.detached {
            do {
                try Renderer.shared.renderPNG(source: source, output: dest, dpi: dpi)
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }

    // MARK: - Drag & drop
    //
    // Behavior:
    //   • Dropping any file replaces the current window's content.
    //
    // To open multiple EPS files simultaneously, use Finder ("Open With…"
    // on multi-selection) or File → Open (⌘O) which accepts multi-select.
    // Both routes go through AppDelegate.spawnWindow(for:) which always
    // creates a fresh window per file.
    //
    // Implementation note: SwiftUI's `.onDrop` only delivers the first
    // NSItemProvider when multiple files are dragged from Finder on
    // macOS 26 — additional providers in the same drop are silently
    // dropped. Iterating doesn't help, so we just take the first one.

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let resolved = url.standardizedFileURL
            DispatchQueue.main.async {
                model.load(url: resolved)
            }
        }
        return true
    }
}

// MARK: - Empty / error states

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Drop an EPS or PostScript file here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("…or use ⌘O to choose a file")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorStateView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text("Couldn't render this file")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - URL helpers

private extension URL {
    /// Returns the URL without its `#fragment` (if any). Used by the
    /// host app to recover the real file URL after AppDelegate adds a
    /// uniqueness fragment to force separate windows for repeated opens.
    var strippingFragment: URL {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        c.fragment = nil
        return c.url ?? self
    }
}
