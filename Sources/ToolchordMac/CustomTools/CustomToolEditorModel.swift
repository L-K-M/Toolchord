import Foundation
import Observation
import ToolchordCore

@MainActor
@Observable
final class CustomToolEditorModel {
    let library: CustomToolLibrary
    var definition: ScriptToolDefinition { didSet { invalidateTrial() } }
    var actionLines: String { didSet { invalidateTrial() } }
    var allowsClipboardWrite: Bool { didSet { invalidateTrial() } }
    var optionsJSON: String { didSet { invalidateTrial() } }
    var regenerateTitle: String { didSet { invalidateTrial() } }
    var sampleOptions: [String: String] = [:] { didSet { invalidateTrial() } }
    var sampleInput = " Hello, Toolchord! " { didSet { invalidateTrial() } }
    var description = ""
    private(set) var trialResult: ToolResult?
    private(set) var trialWasAction = false
    private(set) var isGenerating = false
    private(set) var isRunningTrial = false
    private(set) var message: String?
    private(set) var isError = false
    private(set) var unavailableReason: String?
    private(set) var expected: ScriptToolDefinition?
    @ObservationIgnored private let generator: any ScriptGenerating
    @ObservationIgnored private var baseline: Data?
    @ObservationIgnored private var successfulTrial: Data?
    @ObservationIgnored private var workID = UUID()
    @ObservationIgnored private var workTask: Task<Void, Never>?

    init(library: CustomToolLibrary, generator: any ScriptGenerating = LocalScriptGenerator(), editing id: String? = nil) {
        self.library = library
        self.generator = generator
        unavailableReason = generator.unavailableReason
        let existing = library.definitions.first { $0.id == id }
        let initial = existing ?? Self.newDefinition()
        expected = existing
        definition = initial
        actionLines = Self.lines(for: initial.actions)
        allowsClipboardWrite = initial.capabilities.contains("clipboard.write")
        optionsJSON = Self.optionJSON(initial.options)
        regenerateTitle = initial.regenerateTitle ?? ""
        baseline = try? Self.fingerprint(initial)
    }

    var isBusy: Bool { isGenerating || isRunningTrial }
    var documentID: String { expected?.id ?? "new" }
    var isDirty: Bool { (try? Self.fingerprint(draft())) != baseline }
    var canSave: Bool { !isBusy && successfulTrial != nil && successfulTrial == (try? fingerprintForTrial()) }
    var draftActions: [ScriptToolAction] { (try? draft().actions) ?? [] }
    var declaredOptions: [ScriptOption] { (try? JSONDecoder().decode([ScriptOption].self, from: Data(optionsJSON.utf8))) ?? [] }

    func selectDocument(_ id: String) {
        guard id != documentID else { return }
        guard !isBusy, !isDirty else {
            report("Save or Revert your changes before switching tools.", error: true)
            return
        }
        load(id == "new" ? nil : library.definitions.first { $0.id == id })
    }

    func revert() {
        cancelWork()
        guard library.reload() else {
            report(library.loadProblem ?? "Couldn’t reload your saved tools.", error: true)
            return
        }
        let latest = expected.flatMap { expected in library.definitions.first { $0.id == expected.id } }
        load(latest)
    }

    func generate() {
        guard !isBusy else { return }
        refreshAvailability()
        guard unavailableReason == nil else { report(unavailableReason ?? "Generation is unavailable.", error: true); return }
        let prompt = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.utf8.count <= 4096 else {
            report("Describe your tool in 1 to 4,096 bytes of text.", error: true)
            return
        }
        let current: ScriptToolDefinition
        do { current = try draft() } catch { report(Self.message(for: error), error: true); return }
        isGenerating = true
        message = nil
        let id = UUID()
        workID = id
        let generator = self.generator
        let isNew = expected == nil && !isDirty
        workTask = Task { [weak self] in
            do {
                var generated = try await generator.generate(description: prompt, current: current, isNew: isNew)
                guard !Task.isCancelled, let self, self.workID == id else { return }
                // Generation revises content, never the document identity.
                generated.id = current.id
                try generated.validate()
                self.definition = generated
                self.actionLines = Self.lines(for: generated.actions)
                self.allowsClipboardWrite = generated.capabilities.contains("clipboard.write")
                self.optionsJSON = Self.optionJSON(generated.options)
                self.regenerateTitle = generated.regenerateTitle ?? ""
                self.sampleOptions = [:]
                self.isGenerating = false
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

    func save() {
        guard canSave else {
            report("Run the current draft on your sample successfully before saving.", error: true)
            return
        }
        do {
            let current = try draft()
            try library.save(current, replacing: expected)
            expected = current
            definition = current
            baseline = try Self.fingerprint(current)
            report("Saved. Your tool is available in the palette.")
        } catch {
            report(Self.message(for: error), error: true)
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

    func refreshAvailability() { unavailableReason = generator.unavailableReason }

    /// For tests; UI progress is driven by the observable busy state.
    func waitForIdle() async { await workTask?.value }

    private enum TrialMode: Sendable { case preview, action(String) }

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
                var request = ToolRequest(input: command.input == .none ? .none : .text(sample), options: ToolOptions(options))
                request.seed = command.makeSeed?(SeedContext(now: request.now, options: request.options.resolved(for: command.options)))
                request.cancellation = .currentTask
                switch mode {
                case .preview: return command.run(request)
                case .action(let actionID): return command.performScriptAction(id: actionID, request: request)
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.workID == id else { return }
            self.isRunningTrial = false
            guard (try? self.fingerprintForTrial()) == fingerprint else { return }
            self.trialResult = result
            if case .preview = mode {
                self.trialWasAction = false
                self.successfulTrial = result.isSuccess ? fingerprint : nil
            } else {
                self.trialWasAction = true
                if !result.isSuccess { self.successfulTrial = nil }
            }
            self.report(result.isSuccess ? "Sample completed. Review the result before saving." : (result.problem ?? "The sample failed."), error: !result.isSuccess)
        }
    }

    private func draft() throws -> ScriptToolDefinition {
        var current = definition
        current.actions = try actionLines.split(whereSeparator: \.isNewline).map { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ToolDiagnostic("Write each button as action-id | Button Title, one per line.") }
            return ScriptToolAction(
                id: parts[0].trimmingCharacters(in: .whitespaces),
                title: parts[1].trimmingCharacters(in: .whitespaces)
            )
        }
        current.capabilities = allowsClipboardWrite ? ["clipboard.write"] : []
        do {
            let options = try JSONDecoder().decode([ScriptOption].self, from: Data(optionsJSON.utf8))
            current.options = options.isEmpty && definition.options == nil ? nil : options
        } catch {
            throw ToolDiagnostic("Check the options JSON. Use an array of choices or toggle definitions.")
        }
        let buttonTitle = regenerateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        current.regenerateTitle = buttonTitle.isEmpty ? nil : buttonTitle
        try current.validate()
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
        trialResult = nil
    }

    private func load(_ existing: ScriptToolDefinition?) {
        let value = existing ?? Self.newDefinition()
        expected = existing
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

    private static func newDefinition() -> ScriptToolDefinition {
        ScriptToolDefinition(
            id: "custom.\(UUID().uuidString.lowercased())", title: "Trim Text",
            summary: "Remove surrounding whitespace",
            source: """
            function preview(input, options, api) {
              return input.trim();
            }
            """
        )
    }
}
