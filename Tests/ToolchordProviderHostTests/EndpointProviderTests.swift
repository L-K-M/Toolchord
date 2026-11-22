import Foundation
import Testing
import ToolchordProviderIPC
@testable import ToolchordProviderHost

private final class EndpointFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let auth = request.value(forHTTPHeaderField: "Authorization")
        let reply: (Int, String)
        switch url.host {
        case "catalog.test" where request.httpMethod == "GET" && url.path == "/v1/models" && auth == "Bearer mock-key":
            reply = (200, #"{"data":[{"id":"model-a"},{"id":"model-b"},{"id":"model-a"}]}"#)
        case "anonymous.test" where request.httpMethod == "POST" && url.path == "/custom/v1/chat/completions" && auth == nil:
            let payload = requestBody()
            let messages = payload?["messages"] as? [[String: String]]
            if payload?["model"] as? String == "model-a", messages == [["role": "user", "content": "sample prompt"]] {
                reply = (200, #"{"choices":[{"message":{"content":"result\n"}}]}"#)
            } else { reply = (400, "Unexpected completion request") }
        case "denied.test": reply = (401, "The request contained secret-fixture-key and privately-supplied text.")
        case "bad.test": reply = (200, "{")
        case "truncated.test": reply = (200, #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#)
        default: reply = (404, "")
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func requestBody() -> [String: Any]? {
        if let data = request.httpBody { return try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        return try? JSONSerialization.jsonObject(with: stream) as? [String: Any]
    }

    override func stopLoading() {}
}

@Suite struct EndpointProviderTests {
    private var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EndpointFixture.self]
        return config
    }

    @Test func discoversModelsUsingTheConfiguredKey() async throws {
        let ids = try await EndpointProvider.models(endpoint: "https://catalog.test", key: "mock-key", configuration: configuration)
        #expect(ids == ["model-a", "model-b"])
    }

    @Test func generatesFromAnAnonymousCustomBase() async throws {
        let result = try await EndpointProvider.generate(endpoint: "https://anonymous.test/custom/v1/", key: nil,
                                                        model: "model-a", prompt: "sample prompt", configuration: configuration)
        #expect(result == "result\n")
    }

    @Test func authenticationErrorKeepsCredentialsAndResponseBodyPrivate() async {
        do {
            _ = try await EndpointProvider.models(endpoint: "https://denied.test", key: "secret-fixture-key", configuration: configuration)
            Issue.record("Expected authentication to fail.")
        } catch {
            let message = error.localizedDescription
            #expect(message.contains("credentials"))
            #expect(!message.contains("secret-fixture-key") && !message.contains("privately-supplied"))
        }
    }

    @Test func rejectsMissingOrIncompleteResponses() async {
        await #expect(throws: (any Error).self) {
            try await EndpointProvider.models(endpoint: "https://bad.test", key: nil, configuration: configuration)
        }
        await #expect(throws: (any Error).self) {
            try await EndpointProvider.generate(endpoint: "https://truncated.test", key: nil, model: "model-a",
                                               prompt: "hello", configuration: configuration)
        }
    }

    @Test func endpointScopeIncludesTheServerPortAndDeploymentPath() throws {
        #expect(try ProviderEndpoint.baseURL("https://HOST.test:443/").absoluteString == "https://host.test/v1")
        #expect(try ProviderEndpoint.baseURL("http://[::1]:11434/team/v1/").absoluteString == "http://[::1]:11434/team/v1")
        #expect(try ProviderEndpoint.baseURL("http://127.0.0.2").absoluteString == "http://127.0.0.2/v1")
        for address in ["http://remote.test", "https://user:pass@host.test", "https://host.test/?key=value", "https://host.test/#key"] {
            #expect(throws: (any Error).self) { try ProviderEndpoint.baseURL(address) }
        }
    }

    @Test func refusesToForwardPromptsAndKeysOnRedirect() async throws {
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let original = try #require(URL(string: "https://initial.test/v1/chat/completions"))
        let target = try #require(URL(string: "https://other.test/v1/chat/completions"))
        let redirect = try #require(HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: nil))
        let follow = await withCheckedContinuation { continuation in
            EndpointRedirectPolicy().urlSession(session, task: session.dataTask(with: original),
                                                willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: target)) { follow in
                continuation.resume(returning: follow)
            }
        }
        #expect(follow == nil)
    }
}
