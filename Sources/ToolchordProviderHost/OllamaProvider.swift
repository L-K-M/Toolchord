import Foundation
import ToolchordProviderIPC

enum OllamaProvider {
    static var isInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let executables = (path + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"])
            .filter { $0.hasPrefix("/") }
            .map { $0 + "/ollama" }
            + ["/Applications/Ollama.app/Contents/Resources/ollama", home + "/Applications/Ollama.app/Contents/Resources/ollama"]
        return executables.contains { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }
    }

    static func models(host: String? = ProcessInfo.processInfo.environment["OLLAMA_HOST"],
                       configuration: URLSessionConfiguration = .ephemeral) async throws -> [String] {
        let base = try endpoint(for: host)
        do {
            return try await EndpointProvider.models(endpoint: base.absoluteString, key: nil, configuration: configuration)
        } catch let error as ProviderFailure {
            throw ProviderFailure("Couldn’t list Ollama’s models. Open Ollama or run ollama serve, then refresh. " + error.localizedDescription)
        }
    }

    static func generate(model: String, prompt: String, host: String? = ProcessInfo.processInfo.environment["OLLAMA_HOST"],
                         configuration: URLSessionConfiguration = .ephemeral) async throws -> String {
        let base = try endpoint(for: host)
        do {
            return try await EndpointProvider.generate(endpoint: base.absoluteString, key: nil, model: model,
                                                       prompt: prompt, configuration: configuration)
        } catch let error as ProviderFailure {
            throw ProviderFailure("Ollama couldn’t generate the tool. Check that its server is running and the model is available. " + error.localizedDescription)
        }
    }

    /// Ollama treats a bare hostname as port 11434 and explicit schemes as
    /// their standard ports. Keep any reverse-proxy prefix in front of /v1.
    static func endpoint(for host: String?) throws -> URL {
        var address = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { address = "127.0.0.1:11434" }
        let hasScheme = address.contains("://")
        if address == "::1" { address = "[::1]" }
        guard var parts = URLComponents(string: hasScheme ? address : "http://" + address, encodingInvalidCharacters: false),
              let hostname = parts.host?.lowercased(), ProviderEndpoint.isLoopback(hostname) else {
            throw ProviderFailure("Set OLLAMA_HOST to a loopback address, or choose Custom Endpoint to connect to another server.")
        }
        if !hasScheme && parts.port == nil { parts.port = 11434 }
        guard let server = parts.string else { throw ProviderFailure("Check the local address in OLLAMA_HOST.") }
        let base = try ProviderEndpoint.baseURL(server)
        return base.lastPathComponent == "v1" ? base : base.appending(path: "v1")
    }
}
