import Darwin
import Foundation

@main
enum ProviderProbe {
    static func main() async {
        // A disconnected or unresponsive service must fail this check promptly.
        alarm(120)
        do {
            let client = ProviderHostClient()
            let endpoint = CommandLine.arguments[1]
            let harnesses = try await client.harnesses()
            print("Detected harnesses: " + harnesses.joined(separator: ", "))
            guard Set(harnesses).isSubset(of: ["codex", "claude", "ollama"]) else { throw Failure.invalidReply }
            if CommandLine.arguments.contains("--list-installed-models") {
                for provider in harnesses where provider != "ollama" {
                    let models = try await client.models(provider: provider, endpoint: "")
                    print("\(provider): \(models.count) choices")
                    guard !models.isEmpty else { throw Failure.emptyCatalog(provider) }
                }
            }
            let models = try await client.models(provider: "endpoint", endpoint: endpoint)
            guard models == ["probe-model"] else { throw Failure.invalidReply }
            let result = try await client.generate(provider: "endpoint", endpoint: endpoint, model: models[0], prompt: "Synthetic authoring prompt")
            guard result == "generated fixture" else { throw Failure.invalidReply }
            print("Signed provider passed discovery, model listing and generation.")
        } catch {
            print("Provider integration failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    enum Failure: LocalizedError {
        case invalidReply, emptyCatalog(String)
        var errorDescription: String? {
            switch self {
            case .invalidReply: "Unexpected response from the provider service."
            case let .emptyCatalog(provider): "The installed \(provider) harness returned an empty model catalog."
            }
        }
    }
}
