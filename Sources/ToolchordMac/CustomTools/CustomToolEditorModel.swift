import Foundation
import Observation
import ToolchordCore

@MainActor
@Observable
final class CustomToolEditorModel {
    let library: CustomToolLibrary
    let providers: AuthoringProviderSettings
    /// The complete file is the editable state. Keep the last readable title while a header is incomplete.
    var scriptText: String { didSet { authoringChanged() } }
    private(set) var definition: ScriptToolDefinition
    private(set) var workspaceID: String
    private(set) var scriptProblem: String?
    var sampleOptions: [String: String] = [:] { didSet { invalidateTrial() } }
    var sampleInput = " Hello, Toolchord! " { didSet { invalidateTrial() } }
    var description = ""
    private(set) var trialResult: ToolResult?
    private(set) var trialWasAction = false
    private(set) var isGenerating = false
    private(set) var isRunningTrial = false
    private(set) var message: String?
    private(set) var isError = false
    private var appleUnavailableReason: String?
    private(set) var expected: ScriptToolDefinition?
    @ObservationIgnored private let appleGenerator: any ScriptGenerating
    @ObservationIgnored private let externalGenerator: (String, String, String) -> any ScriptGenerating
    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private var originalFile: PortableToolFile?
    // A portable import can match an installed tool but use different header formatting.
    @ObservationIgnored private var installedAtImport: PortableToolFile?
    @ObservationIgnored private var saveRevision = 0
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    private var baseline: String?
    private var successfulTrial = false
    @ObservationIgnored private var trialRevision = UUID()
    /// Actions tested after a preview use the same captured clock and entropy.
    @ObservationIgnored private var previewRequest: ToolRequest?
    @ObservationIgnored private var workID = UUID()
    @ObservationIgnored private var workTask: Task<Void, Never>?

    init(library: CustomToolLibrary, generator: any ScriptGenerating = LocalScriptGenerator(), editing id: String? = nil,
         providers: AuthoringProviderSettings = AuthoringProviderSettings(),
         externalGenerator: @escaping (String, String, String) -> any ScriptGenerating = {
             ProviderScriptGenerator(provider: $0, endpoint: $1, model: $2)
         }) {
        self.library = library
        self.providers = providers
        self.appleGenerator = generator
        self.externalGenerator = externalGenerator
        appleUnavailableReason = generator.unavailableReason
        let existing = library.definitions.first { $0.id == id }
        let initial = existing ?? Self.newDefinition()
        expected = existing
        workspaceID = initial.id
        definition = initial
        scriptText = ""
        load(existing, content: initial)
        // Give the window a chance to restore a previous journal before any autosave.
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    var unavailableReason: String? {
        providers.selected == .apple ? appleUnavailableReason : providers.generationProblem
    }

    var isBusy: Bool { isGenerating || isRunningTrial }
    var isRevisingTool: Bool { expected != nil || hasDefinitionChanges }
    var documentID: String { expected?.id ?? "new" }
    var hasPendingDescription: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isDirty: Bool { hasPendingDescription || hasDefinitionChanges }
    var canSave: Bool { !isBusy && successfulTrial }
    var draftActions: [ScriptToolAction] { scriptProblem == nil ? definition.actions : [] }
    var declaredOptions: [ScriptOption] { scriptProblem == nil ? definition.options ?? [] : [] }

    func selectDocument(_ id: String) {
        guard id != documentID else { return }
        guard !isBusy, !isDirty else {
            let message = hasPendingDescription
                ? "Generate your pending description or Revert Changes before switching tools."
                : "Save or Revert your changes before switching tools."
            report(message, error: true)
            return
        }
        load(id == "new" ? nil : library.definitions.first { $0.id == id })
        undoManager.removeAllActions()
    }

    func revert() {
        cancelWork()
        guard library.reload() else {
            report(library.loadProblem ?? "Couldn’t reload your saved tools.", error: true)
            return
        }
        let latest = expected.flatMap { expected in library.definitions.first { $0.id == expected.id } }
        let before = captureUndoState()
        if expected == nil {
            if let originalFile {
                load(nil, content: originalFile.definition, source: originalFile)
                baseline = nil
            } else {
                load(nil, content: Self.newDefinition(id: workspaceID))
            }
        } else if let latest {
            load(latest)
        } else {
            report("The installed tool was removed. Export this draft to keep a copy.", error: true)
            return
        }
        registerUndo(before, name: "Revert Changes")
        flushRecovery()
    }

    /// The editor confirms discarding both the installed override and the current draft.
    func restoreBuiltIn() {
        guard !isBusy, let expected, library.isModifiedBuiltIn(id: expected.id),
              let bundled = CustomToolCatalog.bundledByID[expected.id] else { return }
        guard let originalFile = installedAtImport ?? originalFile else {
            report("Reopen the saved tool to load its current version before restoring.", error: true)
            return
        }
        do {
            try library.restoreBuiltIn(replacing: expected, original: originalFile)
            saveRevision += 1
            load(bundled)
            undoManager.removeAllActions()
            flushRecovery()
            report("Restored the built-in version in the library and palette.")
        } catch {
            report(Self.message(for: error), error: true)
        }
    }

    func discardDraft() {
        cancelWork()
        load(expected)
        undoManager.removeAllActions()
        flushRecovery()
    }

    /// Import stages code for inspection. Only Run Sample executes it; Save
    /// remains the explicit, verified installation into the local library.
    func openTool(from url: URL) throws {
        guard !isDirty, !isBusy else {
            throw ScriptToolStore.Error.document(url.lastPathComponent, "Finish editing the current tool before opening another.")
        }
        let file = try PortableToolFile(reading: url)
        guard library.reload() else {
            throw ScriptToolStore.Error.document(url.lastPathComponent, library.loadProblem ?? "Couldn’t read the tool library.")
        }
        let existing = library.definitions.first { $0.id == file.definition.id }
        let installed = try existing.map { try library.document(for: $0.id) }
        let matchesInstalled: Bool
        if let existing, let installed {
            matchesInstalled = try file.hasSameContent(as: installed)
            // A portable customization can be tried against the shipped tool. An
            // already customized or user-created tool keeps its collision protection.
            if !matchesInstalled && (ToolCatalog.command(id: existing.id) == nil || library.isModifiedBuiltIn(id: existing.id)) {
                throw ScriptToolStore.Error.document(url.lastPathComponent,
                    "A different tool with this identifier is installed. Edit the installed tool or give the file a unique custom. identifier.")
            }
        } else {
            matchesInstalled = false
        }
        load(existing, content: file.definition, source: file)
        if let installed, installed.original != file.original { installedAtImport = installed }
        baseline = matchesInstalled ? try installed?.scriptText(for: file.definition) : nil
        undoManager.removeAllActions()
        flushRecovery()
    }

    func exportTool(to url: URL) throws {
        do {
            let current = try draft()
            let edited = try PortableToolFile(scriptText: scriptText)
            // A legacy Open/Export with no semantic edits preserves the original JSON bytes.
            let keepOriginal = try url.pathExtension.lowercased() != "js" && originalFile?.hasSameContent(as: edited) == true
            try PortableToolFile.export(current, preserving: keepOriginal ? originalFile : edited, to: url)
        } catch {
            throw ScriptToolStore.Error.document(url.lastPathComponent, Self.message(for: error))
        }
    }

    /// Called at app lifecycle boundaries as well as after a short typing pause.
    func flushRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        guard let url = library.recoveryURL else { return }
        do {
            if hasDefinitionChanges {
                let recovery = EditorDraftRecovery(scriptText: scriptText, workspaceID: workspaceID, expected: expected,
                                                   baselineText: baseline, originalDocument: originalFile?.original,
                                                   installedAtImport: installedAtImport?.original)
                try recovery.write(to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            report("Couldn’t update draft recovery: \(Self.message(for: error))", error: true)
        }
    }

    @discardableResult
    func restoreRecoveryIfAvailable() -> Bool {
        guard !isBusy, !isDirty, let url = library.recoveryURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let recovery = try JSONDecoder().decode(EditorDraftRecovery.self, from: Data(contentsOf: url))
            var original = try recovery.originalDocument.map(PortableToolFile.init(data:))
            // Early journals recorded only the typed version. Recover its save token
            // when the installed file still matches, including any extension metadata.
            if original == nil, let expected = recovery.expected, let installed = try? library.document(for: expected.id) {
                let recorded = try PortableToolFile(data: PortableToolFile.encode(expected))
                if try recorded.hasSameContent(as: installed) { original = installed }
            }
            let installed = try recovery.installedAtImport.map(PortableToolFile.init(data:))
            expected = recovery.expected
            installedAtImport = installed
            baseline = recovery.baselineText
            originalFile = original
            workspaceID = recovery.workspaceID
            definition = original?.definition ?? expected ?? Self.newDefinition(id: workspaceID)
            scriptText = recovery.scriptText
            description = ""
            sampleOptions = [:]
            undoManager.removeAllActions()
            report("Recovered your tool draft. Run a sample before saving.")
            return true
        } catch {
            report("Couldn’t recover the tool draft: \(Self.message(for: error))", error: true)
            return false
        }
    }

    func generate() {
        guard !isBusy else { return }
        refreshAvailability()
        guard unavailableReason == nil else { report(unavailableReason ?? "Generation is unavailable.", error: true); return }
        let prompt = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedDescription = description
        let submittedScript = scriptText
        guard !prompt.isEmpty, prompt.utf8.count <= 4096 else {
            report("Enter a request between 1 and 4,096 bytes.", error: true)
            return
        }
        let current: ScriptToolDefinition
        let submittedFile: PortableToolFile
        do {
            current = try draft()
            submittedFile = try PortableToolFile(scriptText: scriptText)
        } catch { report(Self.message(for: error), error: true); return }
        isGenerating = true
        message = nil
        let id = UUID()
        workID = id
        let selection = providers.selection
        let generator = selection.provider == .apple ? appleGenerator
            : externalGenerator(selection.provider.rawValue, selection.endpoint, selection.model)
        let isNew = !isRevisingTool
        workTask = Task { [weak self] in
            do {
                var generated = try await generator.generate(description: prompt, current: current, isNew: isNew)
                guard !Task.isCancelled, let self, self.workID == id else { return }
                guard self.providers.selection == selection else {
                    self.isGenerating = false
                    self.report("The provider or model changed. Run Generate again with the current selection.", error: true)
                    return
                }
                guard self.scriptText.hasSameUTF8(as: submittedScript) else {
                    self.isGenerating = false
                    self.report("The script changed during generation. Run Generate again to update your latest edits.", error: true)
                    return
                }
                // Generation revises content, never the document identity.
                generated.id = current.id
                generated.palette = current.palette
                try generated.validate()
                let updated = try submittedFile.scriptText(for: generated)
                let before = self.captureUndoState()
                self.scriptText = updated
                self.sampleOptions = [:]
                if self.description.hasSameUTF8(as: submittedDescription) { self.description = "" }
                self.isGenerating = false
                self.registerUndo(before, name: isNew ? "Generate Tool" : "Generate Update")
                self.report("Draft generated. Run it on your sample before saving.")
            } catch {
                guard !Task.isCancelled, let self, self.workID == id else { return }
                self.isGenerating = false
                self.report(Self.message(for: error), error: true)
            }
        }
    }

    func runSample() { runTrial(.preview) }
    func tryAction(_ id: String) { runTrial(.action(id)) }

    @discardableResult
    func save() -> Bool {
        guard canSave else {
            report("Run the current draft on your sample successfully before saving.", error: true)
            return false
        }
        do {
            let current = try draft()
            let edited = try PortableToolFile(scriptText: scriptText)
            if expected != nil && originalFile == nil {
                throw ToolDiagnostic("Reopen this tool to load its saved file before updating it.")
            }
            try library.save(current, replacing: expected, preserving: installedAtImport ?? originalFile, edited: edited)
            saveRevision += 1
            expected = current
            baseline = scriptText
            originalFile = edited
            installedAtImport = nil
            invalidateTrial()
            flushRecovery()
            report("Saved. Your tool is available in the palette.")
            return true
        } catch {
            report(Self.message(for: error), error: true)
            return false
        }
    }

    func cancelWork() {
        workID = UUID()
        workTask?.cancel()
        workTask = nil
        isGenerating = false
        isRunningTrial = false
    }

    func clearSample() {
        cancelWork()
        sampleInput = ""
        trialResult = nil
    }

    func refreshAvailability() { appleUnavailableReason = appleGenerator.unavailableReason }

    /// For tests; UI progress is driven by the observable busy state.
    func waitForIdle() async { await workTask?.value }

    private enum TrialMode: Sendable { case preview, action(String) }

    private var hasDefinitionChanges: Bool {
        guard let baseline else { return true }
        return !baseline.hasSameUTF8(as: scriptText)
    }

    private struct UndoState {
        let scriptText: String
        let description: String
        let sampleOptions: [String: String]
        let file: PortableToolFile?
        let installedAtImport: PortableToolFile?
        let expected: ScriptToolDefinition?
        let baseline: String?
        let saveRevision: Int
    }

    private func captureUndoState() -> UndoState {
        UndoState(scriptText: scriptText, description: description, sampleOptions: sampleOptions, file: originalFile,
                  installedAtImport: installedAtImport, expected: expected, baseline: baseline, saveRevision: saveRevision)
    }

    private func registerUndo(_ previous: UndoState, name: String) {
        undoManager.registerUndo(withTarget: self) { editor in
            editor.cancelWork()
            editor.registerUndo(editor.captureUndoState(), name: name)
            editor.description = previous.description
            editor.sampleOptions = previous.sampleOptions
            // A Save between the edit and Undo establishes a new on-disk
            // version. Undo its contents without reviving a stale save token.
            if editor.saveRevision == previous.saveRevision {
                editor.originalFile = previous.file
                editor.installedAtImport = previous.installedAtImport
                editor.expected = previous.expected
                editor.baseline = previous.baseline
            }
            editor.scriptText = previous.scriptText
            editor.message = nil
        }
        undoManager.setActionName(name)
    }

    private func authoringChanged() {
        invalidateTrial()
        do {
            let parsed = try ToolScriptDocument(text: scriptText).definition
            let installedID = expected?.id ?? originalFile?.definition.id
            if let installedID {
                guard parsed.id.hasSameUTF8(as: installedID) else {
                    throw ToolDiagnostic("Keep this tool’s identifier \(installedID). Use New Tool to create a different tool.")
                }
            } else if !parsed.id.hasPrefix("custom.") {
                throw ToolDiagnostic("Use a custom. identifier for a new tool. Select a built-in in the library to edit it.")
            }
            try parsed.validateMetadata()
            if parsed.options != definition.options && !sampleOptions.isEmpty {
                sampleOptions = sampleOptions.filter { id, value in
                    guard let option = parsed.options?.first(where: { $0.id == id }) else { return false }
                    return option.choices?.contains(where: { $0.id == value }) ?? ["true", "false"].contains(value)
                }
            }
            definition = parsed
            scriptProblem = nil
        } catch {
            scriptProblem = Self.message(for: error)
        }
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flushRecovery()
        }
    }

    private func runTrial(_ mode: TrialMode) {
        guard !isBusy else { return }
        let current: ScriptToolDefinition
        let command: ToolCommand
        let revision = trialRevision
        do {
            current = try draft()
            command = try current.command()
        } catch { report(Self.message(for: error), error: true); return }
        let sample = sampleInput
        let options = sampleOptions
        let reusedRequest: ToolRequest?
        switch mode {
        case .preview: reusedRequest = nil
        case .action:
            reusedRequest = previewRequest
        }
        guard sample.utf8.count <= ToolLimits.standard.maxInputBytes else {
            report(ToolLimits.standard.inputLimitMessage, error: true)
            return
        }
        let id = UUID()
        workID = id
        isRunningTrial = true
        message = nil
        workTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                var request = reusedRequest ?? ToolRequest(input: command.input == .none ? .none : .text(sample), options: ToolOptions(options))
                if reusedRequest == nil {
                    request.seed = command.makeSeed?(SeedContext(now: request.now, options: request.options.resolved(for: command.options)))
                }
                request.cancellation = .currentTask
                let result: ToolResult
                switch mode {
                case .preview: result = command.run(request)
                case .action(let actionID): result = command.performScriptAction(id: actionID, request: request)
                }
                request.cancellation = .never
                return (result: result, request: request)
            }
            let completion = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.workID == id else { return }
            self.isRunningTrial = false
            guard self.trialRevision == revision else { return }
            let result = completion.result
            self.trialResult = result
            if case .preview = mode {
                self.trialWasAction = false
                self.successfulTrial = result.isSuccess
                self.previewRequest = result.isSuccess ? completion.request : nil
            } else {
                self.trialWasAction = true
                if !result.isSuccess { self.successfulTrial = false }
            }
            self.report(result.isSuccess ? "Sample completed. Review the result before saving." : (result.problem ?? "The sample failed."), error: !result.isSuccess)
        }
    }

    private func draft() throws -> ScriptToolDefinition {
        if let scriptProblem { throw ToolDiagnostic(scriptProblem) }
        return definition
    }

    private func invalidateTrial() {
        trialRevision = UUID()
        successfulTrial = false
        previewRequest = nil
        trialResult = nil
    }

    private func load(_ existing: ScriptToolDefinition?, content: ScriptToolDefinition? = nil, source: PortableToolFile? = nil) {
        let value = content ?? existing ?? Self.newDefinition()
        expected = existing
        workspaceID = value.id
        definition = value
        sampleOptions = [:]
        description = ""
        message = nil
        isError = false
        originalFile = nil
        installedAtImport = nil
        do {
            if let source { originalFile = source }
            else if let existing { originalFile = try library.document(for: existing.id) }
            scriptText = try originalFile?.scriptText(for: value) ?? ToolScriptDocument.text(for: value)
        } catch {
            // Keep the program readable after a disk failure. Save requires the original version.
            scriptText = (try? ToolScriptDocument.text(for: value)) ?? ""
            report(Self.message(for: error), error: true)
        }
        baseline = scriptText
    }

    private func report(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }

    private static func message(for error: any Error) -> String {
        (error as? ToolDiagnostic)?.description ?? error.localizedDescription
    }

    private static func newDefinition(id: String = "custom.\(UUID().uuidString.lowercased())") -> ScriptToolDefinition {
        ScriptToolDefinition(
            id: id, title: "Trim Text",
            summary: "Remove surrounding whitespace",
            source: """
            function preview(input, options, api) {
              return input.trim();
            }
            """
        )
    }
}
