import Foundation
import ToolchordProviderIPC

public enum EndpointProvider {
    public static func models(endpoint: String, key: String?, configuration: URLSessionConfiguration = .ephemeral) async throws -> [String] {
        let url = try ProviderEndpoint.baseURL(endpoint).appending(path: "models")
        let data = try await send(URLRequest(url: url), key: key, configuration: configuration)
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            throw ProviderFailure("The endpoint returned an invalid model list. Check its OpenAI-compatible base URL.")
        }
        var seen = Set<String>()
        return catalog.data.map(\.id).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func generate(endpoint: String, key: String?, model: String, prompt: String,
                                configuration: URLSessionConfiguration = .ephemeral) async throws -> String {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderFailure("Select or enter a model.")
        }
        let url = try ProviderEndpoint.baseURL(endpoint).appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": [["role": "user", "content": prompt]]
        ])

        let data = try await send(request, key: key, configuration: configuration)
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finishReason: String?
            }
            let choices: [Choice]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let choice = (try? decoder.decode(Completion.self, from: data))?.choices.first else {
            throw ProviderFailure("The endpoint returned an invalid chat completion.")
        }
        if choice.finishReason == "length" {
            throw ProviderFailure("The model reached its output limit. Try a shorter request or another model.")
        }
        guard let text = choice.message.content, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderFailure("The selected model returned no text for this request.")
        }
        return text
    }

    static func validate(key: String) throws {
        guard key.utf8.count <= 16 * 1024, key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw ProviderFailure("Enter an API key without spaces or control characters.")
        }
    }

    private static func send(_ original: URLRequest, key: String?, configuration: URLSessionConfiguration) async throws -> Data {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key, !key.isEmpty {
            try validate(key: key)
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        // Each request belongs to a single endpoint and never inherits the
        // user's cookies, cached responses, or unrelated HTTP credentials.
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: EndpointRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderFailure("The endpoint returned an invalid HTTP response.") }
            switch http.statusCode {
            case 200..<300: break
            case 300..<400: throw ProviderFailure("The endpoint redirected the request. Enter the final API base URL.")
            case 401, 403: throw ProviderFailure("The endpoint rejected the credentials. Check its API key and model access.")
            default: throw ProviderFailure("The endpoint returned HTTP \(http.statusCode). Check the base URL and selected model.")
            }
            let maximumBytes = 4 * 1024 * 1024
            guard response.expectedContentLength <= maximumBytes else { throw ProviderFailure("The endpoint response exceeded 4 MiB.") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumBytes else { throw ProviderFailure("The endpoint response exceeded 4 MiB.") }
                data.append(byte)
            }
            return data
        } catch let error as ProviderFailure {
            throw error
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut { throw ProviderFailure("The endpoint timed out. Try again or choose another model.") }
            throw ProviderFailure("Couldn’t reach the endpoint. Check the address, connection, and server certificate.")
        }
    }
}

/// Redirecting a POST can disclose its private prompt even if URLSession
/// drops the Authorization header. Ask the user for the final URL instead.
final class EndpointRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
