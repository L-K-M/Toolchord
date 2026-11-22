import Darwin
import Foundation

public enum ProviderEndpoint {
    /// The base identifies both the credential and the pair of API routes.
    public static func baseURL(_ endpoint: String) throws -> URL {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 4096,
              var parts = URLComponents(string: value, encodingInvalidCharacters: false),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              let encodedHost = parts.percentEncodedHost, !encodedHost.contains("%"),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              !parts.path.contains("\\"), !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { throw ProviderFailure("Enter an API base URL without credentials, a query, or a fragment.") }
        guard scheme == "https" || isLoopback(host) else {
            throw ProviderFailure("Use HTTPS for this endpoint, or HTTP on localhost.")
        }

        parts.scheme = scheme
        parts.host = host
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        parts.percentEncodedPath = path.isEmpty ? "/v1" : path
        guard let url = parts.url else { throw ProviderFailure("Enter a valid API base URL.") }
        return url
    }

    public static func isLoopback(_ host: String) -> Bool {
        if host == "localhost" || host == "localhost." { return true }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, String(host.dropFirst().dropLast()), &address) == 1 else { return false }
            return withUnsafeBytes(of: address) { $0.dropLast().allSatisfy { $0 == 0 } && $0.last == 1 }
        }
        var address = in_addr()
        return inet_pton(AF_INET, host, &address) == 1 && UInt32(bigEndian: address.s_addr) >> 24 == 127
    }
}
