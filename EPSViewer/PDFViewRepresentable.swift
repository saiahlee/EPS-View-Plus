import AppKit
import PDFKit
import SwiftUI

/// SwiftUI bridge to PDFKit's `PDFView`.
///
/// Exposes the underlying `PDFView` to the parent through a `Coordinator`
/// reference, so the toolbar can drive zoom/fit actions without relying on
/// responder-chain spelunking.
struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var coordinator: Coordinator?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        Self.normalizeRotation(of: document)
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = NSColor.windowBackgroundColor

        // (No `usePageViewController` here — that's iOS-only API.
        // macOS PDFView already handles Cmd+scroll/pinch zoom natively.)

        context.coordinator.pdfView = pdfView
        DispatchQueue.main.async {
            coordinator = context.coordinator
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            Self.normalizeRotation(of: document)
            nsView.document = document
            nsView.autoScales = true
        }
    }

    /// Forces every page's display rotation to 0.
    ///
    /// Some EPS files produce PDFs that carry a `/Rotate 90` page entry
    /// — gs sometimes emits that for legitimately-landscape figures.
    /// PDFKit honors that key by default and rotates on display, which
    /// shows the figure sideways. Stamping rotation to 0 here makes the
    /// page render with the orientation actually authored in the EPS.
    private static func normalizeRotation(of document: PDFDocument) {
        for i in 0..<document.pageCount {
            document.page(at: i)?.rotation = 0
        }
    }

    /// Coordinator handed out to the parent so it can drive the PDFView from
    /// outside the SwiftUI body.
    @MainActor
    final class Coordinator {
        weak var pdfView: PDFView?

        private static let zoomStep: CGFloat = 1.25
        private static let minScale: CGFloat = 0.05
        private static let maxScale: CGFloat = 32

        func zoomIn() {
            guard let pdfView else { return }
            pdfView.autoScales = false
            pdfView.scaleFactor = min(pdfView.scaleFactor * Self.zoomStep, Self.maxScale)
        }

        func zoomOut() {
            guard let pdfView else { return }
            pdfView.autoScales = false
            pdfView.scaleFactor = max(pdfView.scaleFactor / Self.zoomStep, Self.minScale)
        }

        func actualSize() {
            guard let pdfView else { return }
            pdfView.autoScales = false
            pdfView.scaleFactor = 1.0
        }

        func fitToWindow() {
            guard let pdfView else { return }
            pdfView.autoScales = true
        }
    }
}
