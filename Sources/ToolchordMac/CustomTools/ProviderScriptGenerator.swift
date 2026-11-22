import Foundation
import ToolchordCore

@MainActor
struct ProviderScriptGenerator: ScriptGenerating {
    let provider, endpoint, model: String

    var unavailableReason: String? {
        ["endpoint", "ollama"].contains(provider) && model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Choose or enter a model to generate a tool." : nil
    }

    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition {
        if let unavailableReason { throw ToolDiagnostic(unavailableReason) }
        let request = try AuthoringPrompt.request(description: description, current: current, isNew: isNew)
        let prompt = AuthoringPrompt.instructions + "\n\n" + Self.format + "\n\n" + request
        let reply = try await ProviderHostClient().generate(provider: provider, endpoint: endpoint, model: model, prompt: prompt)
        try Task.checkCancellation()
        return try Self.parse(reply, id: current.id)
    }

    private static let format = """
    Reply with one JSON object. Required keys: title (short string), summary (string), isGenerator
    (boolean), previewBody (JavaScript statements as a string). Optional keys: options (array),
    actions (array of {id,title}), regenerateTitle (required for generators), performBody,
    makeSeedBody and helpers (strings). Do not include the outer function in a body.
    Example: {"title":"Uppercase","summary":"Uppercase text","isGenerator":false,"previewBody":"return input.toUpperCase();"}
    """

    static func parse(_ reply: String, id: String) throws -> ScriptToolDefinition {
        guard reply.utf8.count <= 512 * 1024 else { throw ToolDiagnostic("The provider returned too much text.") }
        var json = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), let start = json.firstIndex(of: "\n"), json.hasSuffix("```"),
           ["```json", "```"].contains(json[..<start].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            json = String(json[json.index(after: start)...].dropLast(3))
        }
        guard let draft = try? JSONDecoder().decode(AuthoringDraft.self, from: Data(json.utf8)) else {
            throw ToolDiagnostic("The model returned an incomplete tool definition. Try the request again or choose another model.")
        }
        return try draft.definition(id: id)
    }
}
