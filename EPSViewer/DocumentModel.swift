import Combine
import Foundation
import PDFKit

/// Observable state for a single open document.
///
/// One instance per `ViewerWindow`. Renders are kicked off via `load(url:)`,
/// and the view binds to `state` to render the right UI (loading / loaded /
/// error). All transitions happen on the main actor.
@MainActor
final class DocumentModel: ObservableObject {

    enum State {
        case empty
        case loading(URL)
        case loaded(URL, PDFDocument)
        case failed(URL, Error)
    }

    @Published private(set) var state: State = .empty

    var sourceURL: URL? {
        switch state {
        case .empty: return nil
        case .loading(let url), .loaded(let url, _), .failed(let url, _):
            return url
        }
    }

    var document: PDFDocument? {
        if case .loaded(_, let doc) = state { return doc }
        return nil
    }

    func load(url: URL) {
        state = .loading(url)
        Task { [weak self] in
            do {
                let pdfURL = try await Renderer.shared.renderPDF(for: url)
                guard let document = PDFDocument(url: pdfURL) else {
                    await MainActor.run { [weak self] in
                        self?.state = .failed(url, RendererError.outputMissing)
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.state = .loaded(url, document)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed(url, error)
                }
            }
        }
    }
}
