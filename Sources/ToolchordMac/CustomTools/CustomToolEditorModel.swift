import Foundation
import Observation
import ToolchordCore

@MainActor
@Observable
final class CustomToolEditorModel {
    let library: CustomToolLibrary
    let providers: AuthoringProviderSettings
    var definition: ScriptToolDefinition { didSet { authoringChanged() } }
    var actionLines: String { didSet { authoringChanged() } }
    var allowsClipboardWrite: Bool { didSet { authoringChanged() } }
    var optionsJSON: String { didSet { authoringChanged() } }
    var regenerateTitle: String { didSet { authoringChanged() } }
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
    @ObservationIgnored private var saveRevision = 0
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    private var baseline: Data?
    @ObservationIgnored private var successfulTrial: Data?
    /// Actions tested after a preview use the same captured clock and entropy.
    @ObservationIgnored private var previewRequest: (fingerprint: Data, request: ToolRequest)?
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
        originalFile = existing.flatMap { try? library.document(for: $0.id) }
        definition = initial
        actionLines = Self.lines(for: initial.actions)
        allowsClipboardWrite = initial.capabilities.contains("clipboard.write")
        optionsJSON = Self.optionJSON(initial.options)
        regenerateTitle = initial.regenerateTitle ?? ""
        baseline = try? Self.fingerprint(initial)
    }

    var unavailableReason: String? {
        providers.selected == .apple ? appleUnavailableReason : providers.generationProblem
    }

    var isBusy: Bool { isGenerating || isRunningTrial }
    var isRevisingTool: Bool { expected != nil || hasDefinitionChanges }
    var documentID: String { expected?.id ?? "new" }
    var hasPendingDescription: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isDirty: Bool { hasPendingDescription || hasDefinitionChanges }
    var canSave: Bool { !isBusy && successfulTrial != nil && successfulTrial == (try? fingerprintForTrial()) }
    var draftActions: [ScriptToolAction] { (try? draft().actions) ?? [] }
    var declaredOptions: [ScriptOption] { (try? JSONDecoder().decode([ScriptOption].self, from: Data(optionsJSON.utf8))) ?? [] }

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
                load(nil, content: Self.newDefinition(id: definition.id))
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
        guard let originalFile else {
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
        let matchesInstalled: Bool
        if let existing {
            matchesInstalled = try file.hasSameContent(as: library.document(for: existing.id))
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
        // Also mark imports differing only in extension fields as unsaved.
        if !matchesInstalled { baseline = nil }
        undoManager.removeAllActions()
        flushRecovery()
    }

    func exportTool(to url: URL) throws {
        do {
            try PortableToolFile.export(draft(), preserving: originalFile, to: url)
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
                let recovery = EditorDraftFields.Recovery(fields: fields, expected: expected, baseline: baseline,
                                                          originalDocument: originalFile?.original)
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
            let recovery = try JSONDecoder().decode(EditorDraftFields.Recovery.self, from: Data(contentsOf: url))
            let original = try recovery.originalDocument.map(PortableToolFile.init(data:))
            expected = recovery.expected
            baseline = recovery.baseline
            originalFile = original
            apply(recovery.fields)
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
        guard !prompt.isEmpty, prompt.utf8.count <= 4096 else {
            report("Enter a request between 1 and 4,096 bytes.", error: true)
            return
        }
        let current: ScriptToolDefinition
        do { current = try draft() } catch { report(Self.message(for: error), error: true); return }
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
                // Generation revises content, never the document identity.
                generated.id = current.id
                try generated.validate()
                let before = self.captureUndoState()
                self.definition = generated
                self.actionLines = Self.lines(for: generated.actions)
                self.allowsClipboardWrite = generated.capabilities.contains("clipboard.write")
                self.optionsJSON = Self.optionJSON(generated.options)
                self.regenerateTitle = generated.regenerateTitle ?? ""
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
            try library.save(current, replacing: expected, preserving: originalFile)
            saveRevision += 1
            expected = current
            definition = current
            baseline = try Self.fingerprint(current)
            if let savedFile = try? library.document(for: current.id),
               (try? originalFile?.hasSameContent(as: savedFile)) != true {
                originalFile = savedFile
            }
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
        guard let baseline, let current = try? Self.fingerprint(draft()) else { return true }
        return current != baseline
    }

    private var fields: EditorDraftFields {
        EditorDraftFields(definition: definition, actionLines: actionLines, optionsJSON: optionsJSON,
                       regenerateTitle: regenerateTitle, allowsClipboardWrite: allowsClipboardWrite)
    }

    private func apply(_ saved: EditorDraftFields) {
        definition = saved.definition
        actionLines = saved.actionLines
        optionsJSON = saved.optionsJSON
        regenerateTitle = saved.regenerateTitle
        allowsClipboardWrite = saved.allowsClipboardWrite
    }

    private struct UndoState {
        let fields: EditorDraftFields
        let description: String
        let sampleOptions: [String: String]
        let file: PortableToolFile?
        let expected: ScriptToolDefinition?
        let baseline: Data?
        let saveRevision: Int
    }

    private func captureUndoState() -> UndoState {
        UndoState(fields: fields, description: description, sampleOptions: sampleOptions, file: originalFile,
                  expected: expected, baseline: baseline, saveRevision: saveRevision)
    }

    private func registerUndo(_ previous: UndoState, name: String) {
        undoManager.registerUndo(withTarget: self) { editor in
            editor.cancelWork()
            editor.registerUndo(editor.captureUndoState(), name: name)
            editor.apply(previous.fields)
            editor.description = previous.description
            editor.sampleOptions = previous.sampleOptions
            // A Save between the edit and Undo establishes a new on-disk
            // version. Undo its contents without reviving a stale save token.
            if editor.saveRevision == previous.saveRevision {
                editor.originalFile = previous.file
                editor.expected = previous.expected
                editor.baseline = previous.baseline
            }
            editor.message = nil
        }
        undoManager.setActionName(name)
    }

    private func authoringChanged() {
        invalidateTrial()
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
        let fingerprint: Data
        do {
            current = try draft()
            command = try current.command()
            fingerprint = try fingerprintForTrial()
        } catch { report(Self.message(for: error), error: true); return }
        let sample = sampleInput
        let options = sampleOptions
        let reusedRequest: ToolRequest?
        switch mode {
        case .preview: reusedRequest = nil
        case .action:
            reusedRequest = previewRequest?.fingerprint == fingerprint ? previewRequest?.request : nil
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
            guard (try? self.fingerprintForTrial()) == fingerprint else { return }
            let result = completion.result
            self.trialResult = result
            if case .preview = mode {
                self.trialWasAction = false
                self.successfulTrial = result.isSuccess ? fingerprint : nil
                self.previewRequest = result.isSuccess ? (fingerprint, completion.request) : nil
            } else {
                self.trialWasAction = true
                if !result.isSuccess { self.successfulTrial = nil }
            }
            self.report(result.isSuccess ? "Sample completed. Review the result before saving." : (result.problem ?? "The sample failed."), error: !result.isSuccess)
        }
    }

    private func draft() throws -> ScriptToolDefinition {
        var current = definition
        if !actionLines.hasSameUTF8(as: Self.lines(for: definition.actions)) {
            current.actions = try actionLines.split(whereSeparator: \.isNewline).map { line in
                let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { throw ToolDiagnostic("Write each button as action-id | Button Title, one per line.") }
                return ScriptToolAction(
                    id: parts[0].trimmingCharacters(in: .whitespaces),
                    title: parts[1].trimmingCharacters(in: .whitespaces)
                )
            }
        }
        current.capabilities = allowsClipboardWrite ? ["clipboard.write"] : []
        do {
            let options = try JSONDecoder().decode([ScriptOption].self, from: Data(optionsJSON.utf8))
            current.options = options.isEmpty && definition.options == nil ? nil : options
        } catch {
            throw ToolDiagnostic("Check the options JSON. Use an array of choices or toggle definitions.")
        }
        let buttonTitle = regenerateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !regenerateTitle.hasSameUTF8(as: definition.regenerateTitle ?? "") {
            current.regenerateTitle = buttonTitle.isEmpty ? nil : buttonTitle
        }
        return current
    }

    private func fingerprintForTrial() throws -> Data {
        var data = try Self.fingerprint(draft())
        data.append(0)
        data.append(contentsOf: sampleInput.utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        data.append(try encoder.encode(sampleOptions))
        return data
    }

    private static func fingerprint(_ definition: ScriptToolDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(definition)
    }

    private func invalidateTrial() {
        successfulTrial = nil
        previewRequest = nil
        trialResult = nil
    }

    private func load(_ existing: ScriptToolDefinition?, content: ScriptToolDefinition? = nil, source: PortableToolFile? = nil) {
        let value = content ?? existing ?? Self.newDefinition()
        expected = existing
        originalFile = source ?? existing.flatMap { try? library.document(for: $0.id) }
        definition = value
        actionLines = Self.lines(for: value.actions)
        allowsClipboardWrite = value.capabilities.contains("clipboard.write")
        optionsJSON = Self.optionJSON(value.options)
        regenerateTitle = value.regenerateTitle ?? ""
        sampleOptions = [:]
        description = ""
        baseline = try? Self.fingerprint(value)
        message = nil
    }

    private static func lines(for actions: [ScriptToolAction]) -> String {
        actions.map { "\($0.id) | \($0.title)" }.joined(separator: "\n")
    }

    private static func optionJSON(_ options: [ScriptOption]?) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(options ?? [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
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
