import SwiftUI

struct AuthoringProviderControls: View {
    let model: CustomToolEditorModel
    @Bindable var workspace: CustomToolWorkspace

    private var settings: AuthoringProviderSettings { model.providers }
    private var addressChanged: Bool { settings.selected == .endpoint && workspace.providerAddress != settings.endpoint }
    private var keyChanged: Bool { settings.selected == .endpoint && !workspace.providerKey.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Provider", selection: Binding(get: { settings.selected }, set: { settings.select($0) })) {
                    ForEach(settings.choices) { provider in Text(provider.title).tag(provider) }
                }
                Button {
                    model.refreshAvailability()
                    Task { await settings.discover() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(settings.discovering)
                .accessibilityLabel("Check available providers")
                .help("Check installed providers and Apple Intelligence availability")
            }
            if let message = settings.discoveryMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if settings.discovered && settings.detected.isEmpty {
                Text("Codex CLI, Claude Code, and Ollama weren’t found on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if settings.selected == .endpoint { endpointControls }
            if settings.selected != .apple { modelControls }

            if let reason = model.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Text(disclosure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(settings.selected == .apple ? "Generate on This Mac" : "Generate Tool") { model.generate() }
                .disabled(model.isBusy || model.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || model.unavailableReason != nil || addressChanged || keyChanged)
        }
        .task { await settings.discover() }
        .task(id: settings.selected.rawValue + "|" + settings.endpoint) {
            workspace.syncProviderForm(with: settings)
            if settings.selected.requiresInstallation { await settings.loadModels() }
            if settings.selected == .endpoint { await settings.checkKey() }
        }
    }

    private var disclosure: String {
        switch settings.selected {
        case .apple:
            "Apple Intelligence generates the draft on this Mac."
        case .codex, .claude:
            "\(settings.selected.title) uses its configured account and model for your description and, when revising, the current tool definition. Sample input stays in Toolchord."
        case .ollama:
            "Generate sends your description and, when revising, the current tool definition to Ollama on this Mac. The selected model may use Ollama’s cloud. Sample input stays in Toolchord."
        case .endpoint:
            "Generate sends your description and, when revising, the current tool definition to \(settings.endpoint.isEmpty ? "your endpoint" : settings.endpoint). Sample input stays in Toolchord."
        }
    }

    private var endpointControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Endpoint", text: $workspace.providerAddress, prompt: Text("https://example.com/v1"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyAddress() }
                    .accessibilityLabel("OpenAI-compatible API base URL")
                    .help("Use the base URL for the models and chat/completions endpoints.")
                Button("Use Address") { applyAddress() }
                    .disabled(workspace.providerAddress.isEmpty || !addressChanged || settings.savingKey)
            }
            if let problem = settings.endpointMessage {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            if !settings.endpoint.isEmpty && !addressChanged {
                HStack {
                    SecureField(settings.keyStored == true ? "Replace saved API key" : "API key (optional)", text: $workspace.providerKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("API key for this endpoint")
                        .onSubmit { saveKey() }
                    Button("Save Key") { saveKey() }
                        .disabled(workspace.providerKey.isEmpty || settings.savingKey)
                    if settings.keyStored == true {
                        Button("Remove Key") { Task { await settings.updateKey(nil) } }
                            .disabled(settings.savingKey || !workspace.providerKey.isEmpty)
                    }
                }
                if let message = settings.keyMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func applyAddress() {
        guard settings.useEndpoint(workspace.providerAddress) else { return }
        workspace.providerAddress = settings.endpoint
        workspace.providerKey = ""
        workspace.syncProviderForm(with: settings)
    }

    private func saveKey() {
        guard !workspace.providerKey.isEmpty, !addressChanged else { return }
        let submitted = workspace.providerKey
        let destination = settings.endpoint
        Task {
            guard settings.selected == .endpoint, settings.endpoint == destination else { return }
            if await settings.updateKey(submitted), workspace.providerKey == submitted { workspace.providerKey = "" }
        }
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if settings.selected == .ollama {
                    Picker("Model", selection: Binding(get: { settings.model }, set: { settings.setModel($0) })) {
                        Text("Choose an installed model").tag("")
                        if !settings.model.isEmpty && !settings.availableModels.contains(settings.model) {
                            Text("\(settings.model) (last used)").tag(settings.model)
                        }
                        ForEach(settings.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Model", text: Binding(get: { settings.model }, set: { settings.setModel($0) }),
                              prompt: Text(settings.selected.allowsHarnessDefault ? "Harness default" : "Model ID"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Model ID")
                    if !settings.availableModels.isEmpty {
                        Menu("Models") {
                            if settings.selected.allowsHarnessDefault {
                                Button("Harness default") { settings.setModel("") }
                                Divider()
                            }
                            ForEach(settings.availableModels, id: \.self) { modelID in
                                Button(modelID) { settings.setModel(modelID) }
                            }
                        }
                        .fixedSize()
                        .accessibilityLabel("Choose a listed model")
                    }
                }
                Button(settings.loadingModels ? "Loading…" : "List Models") { Task { await settings.loadModels() } }
                    .disabled(settings.loadingModels || (settings.selected == .endpoint && (settings.endpoint.isEmpty || addressChanged || keyChanged || settings.savingKey)))
            }
            .disabled(settings.selected == .endpoint && (addressChanged || settings.endpoint.isEmpty))
            if let message = settings.modelMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
