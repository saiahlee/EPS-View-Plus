import CryptoKit
import Foundation

enum Hashing {
    /// SHA-256 over the tuple `(absolute path, mtime, size)`.
    ///
    /// We deliberately avoid hashing file contents — EPS files can be large,
    /// and hashing them on every preview would defeat the purpose of the cache.
    /// The (path|mtime|size) triple catches every realistic edit while remaining
    /// effectively free to compute.
    static func cacheKey(for url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        let raw = "\(url.path)|\(mtime)|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
