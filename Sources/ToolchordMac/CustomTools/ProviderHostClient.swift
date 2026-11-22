import Foundation
import ToolchordProviderIPC

struct ProviderHostClient: Sendable {
    func harnesses() async throws -> [String] { try await call(.listHarnesses) }
    func models(provider: String, endpoint: String) async throws -> [String] {
        try await call(.listModels(provider: provider, endpoint: endpoint))
    }
    func generate(provider: String, endpoint: String, model: String, prompt: String) async throws -> String {
        try await call(.generate(provider: provider, endpoint: endpoint, model: model, prompt: prompt))
    }
    func hasKey(endpoint: String) async throws -> Bool { try await call(.hasKey(endpoint: endpoint)) }
    func setKey(_ key: String?, endpoint: String) async throws {
        let _: Bool = try await call(.setKey(endpoint: endpoint, key: key))
    }

    private func call<T: Decodable>(_ request: ProviderMessage) async throws -> T {
        let data = try await ProviderExchange().send(JSONEncoder().encode(request))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// One connection per operation lets cancellation retire exactly its request.
/// XPC may deliver a reply, an invalidation, or an error on different threads.
private final class ProviderExchange: @unchecked Sendable {
    private let lock = NSLock()
    private let connection = NSXPCConnection(serviceName: providerServiceName)
    private var continuation: CheckedContinuation<Data, any Error>?
    private var finished = false

    func send(_ data: Data) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                connection.remoteObjectInterface = NSXPCInterface(with: ProviderRemote.self)
                connection.invalidationHandler = { [weak self] in self?.disconnected() }
                connection.interruptionHandler = { [weak self] in self?.disconnected() }
                connection.resume()
                lock.unlock()
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in self?.disconnected() }) as? ProviderRemote else {
                    disconnected()
                    return
                }
                proxy.perform(data) { [weak self] bytes, error in
                    if let bytes { self?.finish(.success(bytes)) }
                    else { self?.finish(.failure(ProviderFailure(error ?? "The provider returned an empty reply."))) }
                }
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    private func disconnected() {
        finish(.failure(ProviderFailure("The authoring provider service disconnected. Reopen the editor in the installed Toolchord app and try again.")))
    }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        connection.invalidate()
        waiting?.resume(with: result)
    }
}
