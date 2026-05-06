import Foundation

/// Manages the cache directory used by the host app, the Quick Look
/// preview extension, and the Thumbnail extension.
///
/// Primary path: an App Group shared container, so the three targets all
/// see the same cache (a render done by one is reused by the others).
/// Fallback path: per-process Caches/EPSViewer, used when the App Group
/// entitlement isn't accepted (which can happen for ad-hoc signed builds
/// distributed without an Apple Developer Program team). The fallback
/// keeps every target individually functional even if cross-target
/// sharing is unavailable.
enum CacheStore {
    /// Resolved cache directory. Always returns a usable path — falls
    /// back to a private per-process directory if the App Group is not
    /// accessible.
    static var directory: URL? {
        if let group = appGroupDirectory() {
            return group
        }
        return privateCacheDirectory()
    }

    /// Resolves the cache file path for a given source EPS/PS URL.
    static func cachedPDFURL(for source: URL) throws -> URL {
        guard let dir = directory else { throw RendererError.cacheUnavailable }
        let key = try Hashing.cacheKey(for: source)
        return dir.appendingPathComponent("\(key).pdf")
    }

    /// Best-effort eviction of cache entries older than `age`.
    static func evict(olderThan age: TimeInterval) {
        guard let dir = directory else { return }
        let cutoff = Date().addingTimeInterval(-age)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []

        for url in urls {
            guard let mtime = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate else { continue }
            if mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Internal

    private static func appGroupDirectory() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        else { return nil }

        let dir = container.appendingPathComponent("EPSViewerCache", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    private static func privateCacheDirectory() -> URL? {
        let base: URL
        if let cachesDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first {
            base = cachesDir
        } else {
            base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        let dir = base.appendingPathComponent("EPSViewer/EPSViewerCache",
                                              isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}
