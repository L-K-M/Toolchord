import CryptoKit
import Foundation

public enum HashTools {
    public static var commands: [ToolCommand] { BundledScripts.commands(in: "hash") }

    enum Algorithm: String { case sha256, sha512, sha1, md5 }

    /// Lowercase hex digest, or `nil` when cancelled. Hashes in chunks so
    /// large input can be cancelled.
    static func hexDigest(of data: Data, algorithm: Algorithm, cancellation: CancellationCheck = .never) -> String? {
        func run<H: HashFunction>(_ hasher: inout H) -> String? {
            let chunk = 64 * 1024
            var offset = 0
            while offset < data.count {
                if cancellation.isCancelled { return nil }
                let end = min(offset + chunk, data.count)
                hasher.update(data: data[offset..<end])
                offset = end
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        switch algorithm {
        case .sha256:
            var hasher = SHA256()
            return run(&hasher)
        case .sha512:
            var hasher = SHA512()
            return run(&hasher)
        case .sha1:
            var hasher = Insecure.SHA1()
            return run(&hasher)
        case .md5:
            var hasher = Insecure.MD5()
            return run(&hasher)
        }
    }
}
