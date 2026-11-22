import Foundation
import ToolchordCore

/// Every authoring provider returns the same JavaScript entry points and metadata.
/// The application supplies document identity and validates the complete program.
struct AuthoringDraft: Decodable {
    let title, summary: String
    let isGenerator: Bool
    let regenerateTitle: String?
    let options: [ScriptOption]?
    let actions: [ScriptToolAction]?
    let previewBody: String
    let performBody, makeSeedBody, helpers: String?

    func definition(id: String) throws -> ScriptToolDefinition {
        guard !previewBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolDiagnostic("The provider returned an empty preview. Revise the description and try again.")
        }
        let buttons = (actions ?? []).filter { !$0.id.isEmpty || !$0.title.isEmpty }
        var parts = ["function preview(input, options, api) {\n" + previewBody + "\n}"]
        if !buttons.isEmpty {
            guard let performBody, !performBody.isEmpty else { throw ToolDiagnostic("Include a performBody for the requested buttons.") }
            parts.append("function perform(action, input, options, api) {\n" + performBody + "\n}")
        }
        if isGenerator, let makeSeedBody { parts.append("function makeSeed(options, api) {\n" + makeSeedBody + "\n}") }
        if let helpers, !helpers.isEmpty { parts.insert(helpers, at: 0) }
        var definition = ScriptToolDefinition(id: id, title: title, summary: summary, source: parts.joined(separator: "\n\n"),
                                              actions: buttons, capabilities: buttons.isEmpty ? [] : ["clipboard.write"])
        // Guided models occasionally emit a completely empty placeholder control.
        // Preserve partial controls so the document validator can report them.
        let controls = (options ?? []).filter {
            !$0.id.isEmpty || !$0.label.isEmpty || !$0.defaultValue.isEmpty || !($0.choices ?? []).isEmpty
        }.map { option in
            var option = option
            let choices = (option.choices ?? []).filter { !$0.id.isEmpty || !$0.label.isEmpty }
            option.choices = choices.isEmpty ? nil : choices
            return option
        }
        definition.options = controls.isEmpty ? nil : controls
        definition.regenerateTitle = isGenerator ? regenerateTitle ?? "" : nil
        try definition.validate()
        return definition
    }
}
