import Foundation
import Observation
import ToolchordProviderIPC

enum AuthoringProvider: String, CaseIterable, Identifiable {
    case apple, codex, claude, ollama, endpoint

    var id: Self { self }

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        case .ollama: "Ollama"
        case .endpoint: "Custom endpoint"
        }
    }

    var allowsHarnessDefault: Bool { self == .codex || self == .claude }
    var requiresInstallation: Bool { allowsHarnessDefault || self == .ollama }
}

@MainActor
protocol AuthoringProviderAccess {
    func harnesses() async throws -> [String]
    func models(provider: String, endpoint: String) async throws -> [String]
    func setKey(_ key: String?, endpoint: String) async throws
    func hasKey(endpoint: String) async throws -> Bool
}

extension ProviderHostClient: AuthoringProviderAccess {}

@Observable @MainActor
final class AuthoringProviderSettings {
    private enum Preference {
        static let provider = "authoring.provider"
        static let endpoint = "authoring.endpoint"
        static let models = "authoring.models"
    }

    struct Selection: Equatable {
        let provider: AuthoringProvider
        let endpoint: String
        let model: String
    }

    private(set) var selected: AuthoringProvider
    private(set) var endpoint: String
    private(set) var model: String
    private(set) var detected: [AuthoringProvider] = []
    private(set) var availableModels: [String] = []
    private(set) var discovered = false
    private(set) var discovering = false
    private(set) var loadingModels = false
    private var listedModels = false
    private(set) var savingKey = false
    private(set) var keyStored: Bool?
    private(set) var discoveryMessage: String?
    private(set) var modelMessage: String?
    private(set) var endpointMessage: String?
    private(set) var keyMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let host: any AuthoringProviderAccess
    @ObservationIgnored private var discoveryID = UUID()
    @ObservationIgnored private var listingID = UUID()
    @ObservationIgnored private var credentialID = UUID()

    init(defaults: UserDefaults = .standard, host: any AuthoringProviderAccess = ProviderHostClient()) {
        self.defaults = defaults
        self.host = host
        let provider = defaults.string(forKey: Preference.provider).flatMap(AuthoringProvider.init(rawValue:)) ?? .apple
        let address = (try? ProviderEndpoint.baseURL(defaults.string(forKey: Preference.endpoint) ?? "").absoluteString) ?? ""
        selected = provider
        endpoint = address
        model = Self.storedModel(in: defaults, provider: provider, endpoint: address)
    }

    var selection: Selection {
        Selection(provider: selected, endpoint: selected == .endpoint ? endpoint : "", model: model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var choices: [AuthoringProvider] {
        AuthoringProvider.allCases.filter { !$0.requiresInstallation || detected.contains($0) || selected == $0 }
    }

    var generationProblem: String? {
        if selected.requiresInstallation && discovered && !detected.contains(selected) {
            return "Toolchord couldn’t find \(selected.title). Install it and check again, or choose another provider."
        }
        if selected == .ollama {
            if selection.model.isEmpty { return "Choose an installed Ollama model." }
            if listedModels && !availableModels.contains(selection.model) {
                return "Your previous Ollama model is unavailable. Choose an installed model."
            }
        }
        if selected == .endpoint {
            if endpoint.isEmpty { return "Enter the base URL of an OpenAI-compatible API." }
            if selection.model.isEmpty { return "Choose a model or enter its ID." }
            if savingKey { return "Saving your API key…" }
        }
        return nil
    }

    func select(_ value: AuthoringProvider) {
        guard value != selected else { return }
        selected = value
        defaults.set(value.rawValue, forKey: Preference.provider)
        resetSelection()
    }

    @discardableResult
    func useEndpoint(_ value: String) -> Bool {
        let address: String
        do {
            address = try ProviderEndpoint.baseURL(value).absoluteString
        } catch {
            endpointMessage = error.localizedDescription
            return false
        }
        endpointMessage = nil
        guard address != endpoint else { return true }
        endpoint = address
        defaults.set(address, forKey: Preference.endpoint)
        resetSelection()
        return true
    }

    func setModel(_ value: String) {
        model = value
        var models = defaults.dictionary(forKey: Preference.models) as? [String: String] ?? [:]
        let key = Self.modelKey(provider: selected, endpoint: endpoint)
        models[key] = value.isEmpty ? nil : value
        defaults.set(models, forKey: Preference.models)
    }

    func discover() async {
        let id = UUID()
        discoveryID = id
        discovering = true
        defer { if discoveryID == id { discovering = false } }
        do {
            let values = try await host.harnesses()
            guard discoveryID == id, !Task.isCancelled else { return }
            detected = AuthoringProvider.allCases.filter { $0.requiresInstallation && values.contains($0.rawValue) }
            discovered = true
            discoveryMessage = nil
        } catch {
            guard discoveryID == id, !Task.isCancelled else { return }
            discoveryMessage = "Couldn’t check installed providers. \(error.localizedDescription)"
        }
    }

    func loadModels() async {
        guard selected != .apple, selected != .endpoint || !endpoint.isEmpty else { return }
        let id = UUID()
        listingID = id
        loadingModels = true
        modelMessage = nil
        defer { if listingID == id { loadingModels = false } }
        do {
            let models = try await host.models(provider: selected.rawValue, endpoint: selection.endpoint)
            guard listingID == id, !Task.isCancelled else { return }
            var seen = Set<String>()
            availableModels = models.filter { !$0.isEmpty && seen.insert($0).inserted }
            listedModels = true
            if availableModels.isEmpty {
                modelMessage = selected == .ollama
                    ? "No installed models were listed. Download a model in Ollama, then list models again."
                    : "No models were listed. Enter a model ID to use it."
            }
        } catch {
            guard listingID == id, !Task.isCancelled else { return }
            modelMessage = selected == .ollama
                ? "Couldn’t list Ollama models. \(error.localizedDescription) Check that the local server is running and try List Models again."
                : "Couldn’t list models. \(error.localizedDescription) You can enter a model ID."
        }
    }

    func checkKey() async {
        guard selected == .endpoint, !endpoint.isEmpty, !savingKey else { return }
        let id = UUID()
        credentialID = id
        do {
            let exists = try await host.hasKey(endpoint: endpoint)
            guard credentialID == id, !Task.isCancelled else { return }
            keyStored = exists
            keyMessage = nil
        } catch {
            guard credentialID == id, !Task.isCancelled else { return }
            keyMessage = "Couldn’t check the saved key. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func updateKey(_ key: String?) async -> Bool {
        guard selected == .endpoint, !endpoint.isEmpty, !savingKey else { return false }
        let id = UUID()
        credentialID = id
        savingKey = true
        defer { if credentialID == id { savingKey = false } }
        do {
            try await host.setKey(key, endpoint: endpoint)
            guard credentialID == id, !Task.isCancelled else { return false }
            keyStored = !(key ?? "").isEmpty
            keyMessage = nil
            return true
        } catch {
            guard credentialID == id, !Task.isCancelled else { return false }
            keyMessage = "Couldn’t change the saved key. \(error.localizedDescription)"
            return false
        }
    }

    private func resetSelection() {
        listingID = UUID()
        credentialID = UUID()
        model = Self.storedModel(in: defaults, provider: selected, endpoint: endpoint)
        availableModels = []
        listedModels = false
        loadingModels = false
        savingKey = false
        keyStored = nil
        keyMessage = nil
        modelMessage = nil
        endpointMessage = nil
    }

    private static func modelKey(provider: AuthoringProvider, endpoint: String) -> String {
        provider == .endpoint ? "endpoint|" + endpoint : provider.rawValue
    }

    private static func storedModel(in defaults: UserDefaults, provider: AuthoringProvider, endpoint: String) -> String {
        defaults.dictionary(forKey: Preference.models)?[modelKey(provider: provider, endpoint: endpoint)] as? String ?? ""
    }
}
