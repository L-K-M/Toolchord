import Foundation
import Security
import ToolchordProviderIPC

public enum AuthoringProviderService {
    public static func run() -> Never {
        let listener = NSXPCListener.service()
        let delegate = ProviderListener()
        listener.delegate = delegate
        return withExtendedLifetime(delegate) { () -> Never in
            listener.resume()
            dispatchMain()
        }
    }
}

private final class ProviderListener: NSObject, NSXPCListenerDelegate {
    // Use the containing app's designated requirement. For an ad-hoc release
    // this pins the actual signed build, including after an in-place update.
    private let clientRequirement: String? = {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return nil }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let clientRequirement else { return false }
        connection.setCodeSigningRequirement(clientRequirement)
        let handler = ProviderHandler()
        connection.exportedInterface = NSXPCInterface(with: ProviderRemote.self)
        connection.exportedObject = handler
        connection.invalidationHandler = { handler.cancel() }
        connection.interruptionHandler = { handler.cancel() }
        connection.resume()
        return true
    }
}

private final class ProviderHandler: NSObject, ProviderRemote, @unchecked Sendable {
    private let lock = NSLock()
    private var work: Task<Void, Never>?
    private var closed = false

    func perform(_ data: Data, withReply reply: @escaping @Sendable (Data?, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, work == nil, data.count <= 2 * 1024 * 1024 else {
            reply(nil, "Invalid authoring request.")
            return
        }
        work = Task {
            do {
                let request = try JSONDecoder().decode(ProviderMessage.self, from: data)
                let result = try await Self.handle(request)
                try Task.checkCancellation()
                reply(result, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func cancel() {
        lock.lock()
        closed = true
        let task = work
        lock.unlock()
        task?.cancel()
    }

    private static func handle(_ request: ProviderMessage) async throws -> Data {
        let encoder = JSONEncoder()
        switch request {
        case .listHarnesses:
            return try encoder.encode(LocalHarness.available() + (OllamaProvider.isInstalled ? ["ollama"] : []))
        case let .hasKey(endpoint):
            return try encoder.encode(EndpointCredentials.read(endpoint: endpoint) != nil)
        case let .setKey(endpoint, key):
            try EndpointCredentials.store(key, endpoint: endpoint)
            return try encoder.encode(true)
        case let .listModels(provider, endpoint):
            if provider == "ollama" { return try await encoder.encode(OllamaProvider.models()) }
            if provider == "endpoint" {
                let key = try EndpointCredentials.read(endpoint: endpoint)
                return try await encoder.encode(EndpointProvider.models(endpoint: endpoint, key: key))
            }
            return try await encoder.encode(LocalHarness.models(provider: provider))
        case let .generate(provider, endpoint, model, prompt):
            guard (["codex", "claude"].contains(provider) || !model.isEmpty), model.utf8.count <= 512, !prompt.isEmpty, prompt.utf8.count <= 1024 * 1024 else {
                throw ProviderFailure("Choose a model and a tool description within the supported size.")
            }
            if provider == "ollama" { return try await encoder.encode(OllamaProvider.generate(model: model, prompt: prompt)) }
            if provider == "endpoint" {
                let key = try EndpointCredentials.read(endpoint: endpoint)
                return try await encoder.encode(EndpointProvider.generate(endpoint: endpoint, key: key, model: model, prompt: prompt))
            }
            return try await encoder.encode(LocalHarness.generate(provider: provider, model: model, prompt: prompt))
        }
    }
}
