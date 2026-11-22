import Foundation
import ToolchordCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol ScriptGenerating {
    var unavailableReason: String? { get }
    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition
}

/// Uses Apple's on-device model explicitly. No remote provider is selected.
@MainActor
struct LocalScriptGenerator: ScriptGenerating {
    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn’t support Apple Intelligence. You can edit the JavaScript below."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to generate a tool, or edit the JavaScript below."
            case .unavailable(.modelNotReady):
                return "The on-device model is still getting ready. Try again later, or edit the JavaScript below."
            @unknown default:
                return "The on-device model is unavailable. You can edit the JavaScript below."
            }
        }
        #endif
        return "On-device generation requires macOS 26 and Apple Intelligence. You can edit the JavaScript below."
    }

    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition {
        if let reason = unavailableReason { throw ToolDiagnostic(reason) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
            let context: String
            if isNew {
                context = "Create a new tool. Start with empty options and actions unless requested."
            } else {
                // Present editable code verbatim and omit the opaque document ID.
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let controls = String(decoding: try encoder.encode(current.options ?? []), as: UTF8.self)
                let actions = String(decoding: try encoder.encode(current.actions), as: UTF8.self)
                context = """
                Revise the existing JavaScript below to implement the request. The new preview still
                receives the original input, not the previous result. Make the smallest change that
                fulfills the request. Preserve controls unless asked to change them.
                Title: \(current.title)
                Purpose: \(current.summary)
                Options: \(controls)
                Actions: \(actions)
                Regenerate button: \(current.regenerateTitle ?? "none")
                Existing JavaScript:
                \(current.source)
                """
            }
            let prompt = "\(context)\n\nUser request:\n\(description)"
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
        #endif
        throw ToolDiagnostic("The on-device model is unavailable.")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func definition(from draft: ModelDraft, id: String) throws -> ScriptToolDefinition {
        // A completely empty array element is a placeholder, not a control.
        // Partially filled controls still go through the normal validator.
        let actions = (draft.actions ?? []).filter { !$0.id.isEmpty || !$0.title.isEmpty }
        let options = (draft.options ?? []).filter { !$0.id.isEmpty || !$0.label.isEmpty || !$0.defaultValue.isEmpty || !$0.choices.isEmpty }
        // The editor stores ordinary JavaScript. Supplying the signatures here
        // keeps the model focused on the requested logic and its arguments.
        var parts = ["function preview(input, options, api) {\n" + draft.previewBody + "\n}"]
        if !actions.isEmpty {
            guard let body = draft.performBody, !body.isEmpty else { throw ToolDiagnostic("Include a performBody for the requested buttons.") }
            parts.append("function perform(action, input, options, api) {\n" + body + "\n}")
        }
        if draft.isGenerator, let body = draft.makeSeedBody {
            parts.append("function makeSeed(options, api) {\n" + body + "\n}")
        }
        if let helpers = draft.helpers, !helpers.isEmpty { parts.insert(helpers, at: 0) }
        var definition = ScriptToolDefinition(
            id: id, title: draft.title, summary: draft.summary, source: parts.joined(separator: "\n\n"),
            actions: actions.map { ScriptToolAction(id: $0.id, title: $0.title) },
            capabilities: actions.isEmpty ? [] : ["clipboard.write"]
        )
        definition.options = options.isEmpty ? nil : options.map { option in
            let choices = option.choices.filter { !$0.id.isEmpty || !$0.label.isEmpty }
            return ScriptOption(id: option.id, label: option.label, defaultValue: option.defaultValue,
                                choices: choices.isEmpty ? nil : choices.map { ScriptOption.Choice(id: $0.id, label: $0.label) })
        }
        definition.regenerateTitle = draft.isGenerator ? draft.regenerateTitle : nil
        try definition.validate()
        return definition
    }

    @available(macOS 26.0, *)
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

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct ModelOption {
        var id: String
        var label: String
        @Guide(description: "Default choice ID, or the string true or false for a toggle")
        var defaultValue: String
        @Guide(description: "Empty array for a toggle. Otherwise the available choices, including the default.")
        var choices: [ModelChoice]
    }

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct ModelChoice {
        var id: String
        var label: String
    }

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct ModelAction {
        var id: String
        var title: String
    }
    #endif

    private static let instructions = """
    Implement the requested tool in synchronous JavaScriptCore. The host wraps your JavaScript
    statements in functions. Supply function bodies only, without tests or calls at global scope.
    No imports, Node, DOM, Web Crypto, fetch, promises, or file access. Use the host methods below.
    Inside previewBody, input is the entire input string, including spaces. Return the transformed
    string directly, or return {primaryText, status, fields: [{id,label,value}]}. For example,
    the previewBody of an uppercase tool is just: return input.toUpperCase();
    For malformed input, throw Error with a helpful message. A preview cannot perform side effects.

    These are the host's JavaScript calls (arguments in order):
    api.native("crypto.digest", algorithm, input) returns a lowercase hex string; algorithm is
    "md5", "sha1", "sha256", or "sha512". api.native("crypto.hkdfHex", hexKey, context, byteCount)
    derives key material. api.native("text.transliterate", input) transliterates text.
    api.native("text.byteCountLabel", input) formats its UTF-8 size.
    api.native("text.numericType", character) returns "decimal", "digit", "numeric" or "".
    api.native("text.graphemeClasses", input) returns one marker per grapheme: W for whitespace, O otherwise.
    api.native("text.compare", a, b, caseSensitive) returns -1, 0 or 1 with numeric ordering.
    api.native("clock.offsetSeconds", unixMilliseconds) returns the local zone offset in seconds.
    api.native("markdown.parse", input) returns a flat tree {nodes} or an error object.

    Most tools have options=[] and actions=[]. Add controls only when requested.
    In metadata, a toggle uses {id,label,defaultValue:"false",choices:[]}. A choice uses
    {id,label,defaultValue,choices:[{id,label}]}. Inside JavaScript, options[id] is a string.
    Only declare actions for requested buttons. Their performBody calls api.clipboard.writeText(text)
    exactly once per action. Normal result copying is built in. Optional helpers can be shared
    between preview and actions.

    Set isGenerator=false and regenerateTitle="" for any tool that takes input.
    For a tool that generates values without input, set isGenerator=true with a regenerateTitle.
    api.now is Unix milliseconds and api.seed is stable until Regenerate. Use these instead of Date.now
    and Math.random. A generator can supply a makeSeedBody to derive a string
    seed from api.entropy, an array of random bytes. Preserve existing controls on revisions.
    """
}
