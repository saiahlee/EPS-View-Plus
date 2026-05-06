import AppKit
import PDFKit
import QuickLookThumbnailing

/// Thumbnail extension entry point.
///
/// macOS calls this from a sandboxed `com.apple.quicklook.thumbnail`
/// extension process whenever Finder, Spotlight, or any client needs a
/// thumbnail bitmap for an EPS or PostScript file.
final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        Task {
            do {
                let pdfURL = try await Renderer.shared.renderPDF(for: request.fileURL)
                guard let document = PDFDocument(url: pdfURL),
                      let page = document.page(at: 0) else {
                    handler(nil, RendererError.outputMissing)
                    return
                }

                // Normalize any /Rotate metadata so the thumbnail dimensions
                // match the figure's actual orientation in the EPS.
                page.rotation = 0

                let pageRect = page.bounds(for: .mediaBox)
                guard pageRect.width > 0, pageRect.height > 0 else {
                    handler(nil, RendererError.outputMissing)
                    return
                }

                let scaleX = request.maximumSize.width / pageRect.width
                let scaleY = request.maximumSize.height / pageRect.height
                let scale = max(min(scaleX, scaleY), 0.01)
                let outputSize = NSSize(
                    width: pageRect.width * scale,
                    height: pageRect.height * scale)

                let reply = QLThumbnailReply(contextSize: outputSize) { context in
                    // Fill with a transparent background; tools like Finder
                    // composite us onto their own backgrounds.
                    context.clear(CGRect(origin: .zero, size: outputSize))

                    NSGraphicsContext.saveGraphicsState()
                    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                    NSGraphicsContext.current = nsContext

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
