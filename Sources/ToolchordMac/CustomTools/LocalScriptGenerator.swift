import Foundation
import FoundationModels
import ToolchordCore

@MainActor
protocol ScriptGenerating {
    var unavailableReason: String? { get }
    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition
}

/// Uses Apple's on-device model explicitly. No remote provider is selected.
@MainActor
struct LocalScriptGenerator: ScriptGenerating {
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn’t support Apple Intelligence. You can edit the JavaScript in the Script tab."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to generate a tool, or edit the JavaScript in the Script tab."
        case .unavailable(.modelNotReady):
            return "The on-device model is still getting ready. Try again later, or edit the JavaScript in the Script tab."
        @unknown default:
            return "The on-device model is unavailable. You can edit the JavaScript in the Script tab."
        }
    }

    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition {
        if let reason = unavailableReason { throw ToolDiagnostic(reason) }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: AuthoringPrompt.instructions)
        let prompt = try AuthoringPrompt.request(description: description, current: current, isNew: isNew)
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 3000)
        let response = try await session.respond(to: prompt, generating: ModelDraft.self, options: options)
        try Task.checkCancellation()
        do {
            return try Self.definition(from: response.content, id: current.id)
        } catch {
            // Guided generation guarantees types, but the source and option
            // defaults must also satisfy the tool contract. Give the model
            // its precise validation error once before returning to the editor.
            let repair = "Correct your draft: " + error.localizedDescription +
                " Preserve the requested behavior. Omit unused options and actions."
            let revision = try await session.respond(to: repair, generating: ModelDraft.self, options: options)
            try Task.checkCancellation()
            return try Self.definition(from: revision.content, id: current.id)
        }
    }

    private static func definition(from draft: ModelDraft, id: String) throws -> ScriptToolDefinition {
        let options = draft.options?.map { option in
            ScriptOption(id: option.id, label: option.label, defaultValue: option.defaultValue,
                         choices: option.choices.map { ScriptOption.Choice(id: $0.id, label: $0.label) })
        }
        return try AuthoringDraft(title: draft.title, summary: draft.summary, isGenerator: draft.isGenerator,
                                  regenerateTitle: draft.regenerateTitle, options: options,
                                  actions: draft.actions?.map { ScriptToolAction(id: $0.id, title: $0.title) },
                                  previewBody: draft.previewBody, performBody: draft.performBody,
                                  makeSeedBody: draft.makeSeedBody, helpers: draft.helpers).definition(id: id)
    }

    @Generable
    fileprivate struct ModelDraft {
        @Guide(description: "A short verb-first title for the tool")
        var title: String
        @Guide(description: "One line describing what this tool does")
        var summary: String
        @Guide(description: "False for every text transformation or inspection. True ONLY for a requested generator that needs no input text.")
        var isGenerator: Bool
        @Guide(description: "Empty for text tools. For a generator, a short button label such as Generate Again.")
        var regenerateTitle: String
        @Guide(description: "Omit unless the user asks for configurable controls or the existing tool has options.")
        var options: [ModelOption]?
        @Guide(description: "Omit unless the user asks for custom clipboard buttons or the existing tool has actions.")
        var actions: [ModelAction]?
        @Guide(description: "JavaScript statements INSIDE preview(input, options, api). Return the computed value with a return statement. No enclosing function, test invocation, or Markdown fences.")
        var previewBody: String
        @Guide(description: "Only for declared action buttons: JavaScript statements inside perform(action, input, options, api).")
        var performBody: String?
        @Guide(description: "Only for a generator that needs a custom seed: statements inside makeSeed(options, api). Otherwise omit.")
        var makeSeedBody: String?
        @Guide(description: "Optional shared helper function declarations used by multiple entry points. No test calls or executable examples.")
        var helpers: String?
    }

    @Generable
    fileprivate struct ModelOption {
        var id: String
        var label: String
        @Guide(description: "Default choice ID, or the string true or false for a toggle")
        var defaultValue: String
        @Guide(description: "Empty array for a toggle. Otherwise the available choices, including the default.")
        var choices: [ModelChoice]
    }

    @Generable
    fileprivate struct ModelChoice {
        var id: String
        var label: String
    }

    @Generable
    fileprivate struct ModelAction {
        var id: String
        var title: String
    }
}
