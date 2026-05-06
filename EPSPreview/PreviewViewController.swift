import Cocoa
import PDFKit
import Quartz

/// Quick Look preview extension entry point.
///
/// macOS instantiates this class (in a sandboxed `com.apple.quicklook.preview`
/// extension process) when the user spacebars an `.eps` or `.ps` in Finder.
///
/// We render the EPS into a PDF via Ghostscript, then display it in a
/// `PDFView` configured to fill the Quick Look panel. The host's metadata
/// header (filename, file size, modified date) is reduced to its minimum
/// by reporting a large `preferredContentSize` and rendering edge-to-edge.
final class PreviewViewController: NSViewController, QLPreviewingController {

    // MARK: - Subviews

    private let pdfView: PDFView = {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let progressIndicator: NSProgressIndicator = {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isIndeterminate = true
        return spinner
    }()

    private let errorLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }()

    // MARK: - View lifecycle

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        root.addSubview(pdfView)
        root.addSubview(progressIndicator)
        root.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: root.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            progressIndicator.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            errorLabel.widthAnchor.constraint(
                lessThanOrEqualTo: root.widthAnchor, multiplier: 0.85),
        ])

        view = root

        // Tell Quick Look we'd like the largest practical preview area.
        // Quick Look's panel will use this to size the body region while
        // shrinking the metadata header to a minimum.
        preferredContentSize = NSSize(width: 1024, height: 768)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Re-fit after the panel finishes sizing the view so the figure
        // fills the entire available area regardless of its aspect ratio.
        fitPDFToView()
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.showLoading() }
            do {
                let pdfURL = try await Renderer.shared.renderPDF(for: url)
                let document = PDFDocument(url: pdfURL)
                if let document {
                    for i in 0..<document.pageCount {
                        document.page(at: i)?.rotation = 0
                    }
                }
                await MainActor.run {
                    if let document {
                        self.show(document: document)
                        handler(nil)
                    } else {
                        self.show(error: RendererError.outputMissing)
                        handler(nil)
                    }
                }
            } catch {
                await MainActor.run {
                    self.show(error: error)
                    handler(nil)
                }
            }
        }
    }

    // MARK: - State helpers

    @MainActor
    private func showLoading() {
        pdfView.document = nil
        pdfView.isHidden = true
        errorLabel.isHidden = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
    }

    @MainActor
    private func show(document: PDFDocument) {
        pdfView.document = document
        pdfView.isHidden = false
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        errorLabel.isHidden = true
        fitPDFToView()
    }

    @MainActor
    private func show(error: Error) {
        pdfView.document = nil
        pdfView.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        errorLabel.stringValue = error.localizedDescription
        errorLabel.isHidden = false
    }

    /// Sizes the PDF page to fill the available width or height, whichever
    /// is the limiting dimension. autoScales alone is unreliable inside
    /// Quick Look extensions because the panel resizes us multiple times
    /// during preview prep — explicit fit avoids the "tiny figure on a
    /// large background" effect.
    @MainActor
    private func fitPDFToView() {
        guard let page = pdfView.document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }
        let viewSize = pdfView.bounds.size
        guard viewSize.width > 1, viewSize.height > 1 else {
            // View not laid out yet — try again after the next layout pass.
            DispatchQueue.main.async { [weak self] in self?.fitPDFToView() }
            return
        }
        let scaleX = viewSize.width  / pageBounds.width
        let scaleY = viewSize.height / pageBounds.height
        let scale = min(scaleX, scaleY)
        // Disable autoScales so our manual fit isn't overridden on the
        // next layout, then apply the scale.
        pdfView.autoScales = false
        pdfView.scaleFactor = scale
        // Re-center after scaling.
        if let firstPage = pdfView.document?.page(at: 0) {
            pdfView.go(to: PDFDestination(page: firstPage, at: NSPoint.zero))
        }
    }
}
