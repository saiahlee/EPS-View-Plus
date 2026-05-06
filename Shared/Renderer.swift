import Foundation

enum RendererError: LocalizedError {
    case cacheUnavailable
    case outputMissing
    case converterMissing(URL)

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable:
            return "Cache directory is not accessible. The app could not create or write to its cache folder."
        case .outputMissing:
            return "Converter reported success but produced no output file."
        case .converterMissing(let url):
            return "Bundled converter binary not found at \(url.path)."
        }
    }
}

/// EPS/PS → PDF renderer with App-Group-shared caching.
///
/// Singleton actor — used identically by the host app, the Quick Look
/// preview extension, and the thumbnail extension. Each target carries its
/// own copy of the converter binary inside `Contents/Tools/`, but they all
/// share the same on-disk cache.
actor Renderer {
    static let shared = Renderer()

    private var inflight: [String: Task<URL, Error>] = [:]

    /// Returns a cached PDF URL for the given EPS/PS file, rendering if needed.
    /// Concurrent callers for the same file coalesce onto a single render.
    func renderPDF(for source: URL) async throws -> URL {
        let target = try CacheStore.cachedPDFURL(for: source)
        let key = target.path

        // Honor the cache only if the file is non-empty AND looks like a
        // valid PDF (a previous failed render may have left behind a
        // zero-byte placeholder, which would otherwise be returned as a
        // valid cache hit and break PDFKit on the next launch).
        if Renderer.isUsableCachedPDF(at: target) {
            return target
        }
        // Discard any stale or corrupt cache entry so we re-render below.
        try? FileManager.default.removeItem(at: target)

        if let existing = inflight[key] {
            return try await existing.value
        }

        // Run the gs invocation off the actor (it's blocking I/O and we
        // don't want to occupy the actor's serial executor while it runs).
        let task = Task<URL, Error>.detached {
            try Renderer.runConverter(source: source, output: target)
            return target
        }
        inflight[key] = task

        do {
            let url = try await task.value
            inflight[key] = nil
            return url
        } catch {
            inflight[key] = nil
            // Clean up any partial output so the next call doesn't trust it.
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    /// A minimal validity check: cached file exists, is non-empty, and
    /// starts with the PDF magic bytes (`%PDF-`).
    private nonisolated static func isUsableCachedPDF(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > 0
        else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 5)) ?? Data()
        return head == Data("%PDF-".utf8)
    }

    /// One-off PNG render to a caller-chosen location, used for Export.
    /// Not cached — the cache is for the canonical PDF only.
    nonisolated func renderPNG(source: URL, output: URL, dpi: Int) throws {
        let converter = Renderer.converterURL()
        try ProcessRunner.run(executable: converter, arguments: [
            "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dSAFER",
            "-dEPSCrop",
            "-dTextAlphaBits=4", "-dGraphicsAlphaBits=4",
            "-sDEVICE=png16m",
            "-r\(dpi)",
            "-sOutputFile=\(output.path)",
            source.path,
        ])
    }

    /// Direct PDF copy from cache to an arbitrary destination, used for
    /// Export → PDF. Renders into the cache if not already present.
    func exportPDF(from source: URL, to destination: URL) async throws {
        let cached = try await renderPDF(for: source)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: cached, to: destination)
    }

    // ────────────────────────────────────────────────────────────────────
    // Private helpers (nonisolated → callable from any thread)
    // ────────────────────────────────────────────────────────────────────

    private nonisolated static func runConverter(source: URL, output: URL) throws {
        let converter = converterURL()
        try ProcessRunner.run(executable: converter, arguments: [
            "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dSAFER",
            "-dEPSCrop",
            // Force gs to never auto-rotate the page or write a /Rotate
            // entry. Without this, gs makes "landscape-looking" EPS
            // figures (where BoundingBox width > height) into a portrait
            // PDF page with /Rotate 90, which Preview.app honors silently
            // but PDFKit applies on display, showing the figure sideways.
            // /None keeps the geometry exactly as the EPS authored it.
            "-dAutoRotatePages=/None",
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-sOutputFile=\(output.path)",
            source.path,
        ])
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw RendererError.outputMissing
        }
    }

    /// Resolves the converter binary alongside the calling bundle.
    ///
    /// The host app and each extension each carry their own copy under
    /// `Contents/Tools/converter` to satisfy App Sandbox exec rules — the
    /// sandbox only permits exec of binaries inside the calling bundle.
    ///
    /// We deliberately do NOT pre-check `fileExists` / `isExecutableFile`:
    /// inside an App Sandbox extension, those APIs can return false for
    /// files that DO exist and ARE executable (the sandbox returns
    /// "no permission" rather than the truth). Instead we let
    /// `ProcessRunner` attempt to spawn and surface any real error.
    private nonisolated static func converterURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Tools/converter")
    }
}
