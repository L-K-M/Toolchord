import Foundation
import Testing
@testable import ToolchordProviderHost

private final class OllamaFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "127.0.0.1", url.port == 12000,
              request.value(forHTTPHeaderField: "Authorization") == nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body: String
        switch (request.httpMethod, url.path) {
        case ("GET", "/proxy/v1/models"):
            body = #"{"data":[{"id":"example:7b"},{"id":"example:cloud"}]}"#
        case ("POST", "/proxy/v1/chat/completions"):
            body = #"{"choices":[{"message":{"content":"generated source"}}]}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite struct OllamaProviderTests {
    private var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaFixture.self]
        return config
    }

    @Test func honorsOllamaHostAndPortConventions() throws {
        #expect(try OllamaProvider.endpoint(for: nil).absoluteString == "http://127.0.0.1:11434/v1")
        #expect(try OllamaProvider.endpoint(for: "localhost").absoluteString == "http://localhost:11434/v1")
        #expect(try OllamaProvider.endpoint(for: "https://localhost").absoluteString == "https://localhost/v1")
        #expect(try OllamaProvider.endpoint(for: "[::1]:9000/proxy/v1/").absoluteString == "http://[::1]:9000/proxy/v1")
        for host in ["https://remote.test", "remote.test:11434", "http://localhost@remote.test", "https://localhost.evil.test", "https://someone:token@localhost"] {
            #expect(throws: (any Error).self) { try OllamaProvider.endpoint(for: host) }
        }
    }

    @Test func usesTheLocalServerForModelsAndGenerationWithoutCredentials() async throws {
        let host = "127.0.0.1:12000/proxy"
        let models = try await OllamaProvider.models(host: host, configuration: configuration)
        #expect(models == ["example:7b", "example:cloud"])
        let draft = try await OllamaProvider.generate(model: "example:7b", prompt: "Build my tool.", host: host, configuration: configuration)
        #expect(draft == "generated source")
    }

    @Test func stoppedServersExplainHowToRefresh() async {
        do {
            _ = try await OllamaProvider.models(host: "127.0.0.1:12000/offline", configuration: configuration)
            Issue.record("Expected an offline failure.")
        } catch {
            #expect(error.localizedDescription.contains("ollama serve"))
        }
    }
}
