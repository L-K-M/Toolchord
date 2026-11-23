import Foundation
import ToolchordCore

/// Private recovery keeps incomplete authoring text, including malformed headers.
struct EditorDraftRecovery: Codable {
    let scriptText: String
    let workspaceID: String
    let expected: ScriptToolDefinition?
    let baselineText: String?
    let originalDocument: Data?
    let installedAtImport: Data?

    init(scriptText: String, workspaceID: String, expected: ScriptToolDefinition?, baselineText: String?,
         originalDocument: Data?, installedAtImport: Data?) {
        self.scriptText = scriptText
        self.workspaceID = workspaceID
        self.expected = expected
        self.baselineText = baselineText
        self.originalDocument = originalDocument
        self.installedAtImport = installedAtImport
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expected = try values.decodeIfPresent(ScriptToolDefinition.self, forKey: .expected)
        installedAtImport = try values.decodeIfPresent(Data.self, forKey: .installedAtImport)
        originalDocument = try values.decodeIfPresent(Data.self, forKey: .originalDocument)
        if let raw = try values.decodeIfPresent(String.self, forKey: .scriptText) {
            scriptText = raw
            workspaceID = try values.decode(String.self, forKey: .workspaceID)
            baselineText = try values.decodeIfPresent(String.self, forKey: .baselineText)
        } else {
            // Before tools were edited as a single file, unfinished controls and JavaScript
            // lived in separate fields. Preserve the typed values even when incomplete.
            let legacy = try LegacyDraft(from: decoder)
            let original = try originalDocument.map(PortableToolFile.init(data:))
            scriptText = try legacy.fields.scriptText(preserving: original)
            workspaceID = legacy.fields.definition.id
            baselineText = try legacy.baseline.map { data in
                let value = try JSONDecoder().decode(ScriptToolDefinition.self, from: data)
                return try original?.scriptText(for: value) ?? ToolScriptDocument.text(for: value)
            }
        }
    }

    func write(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    private struct LegacyDraft: Decodable {
        let fields: Fields
        let baseline: Data?

        struct Fields: Decodable {
            var definition: ScriptToolDefinition
            let actionLines, optionsJSON, regenerateTitle: String
            let allowsClipboardWrite: Bool

            func scriptText(preserving original: PortableToolFile?) throws -> String {
                var value = definition
                let originalLines = value.actions.map { "\($0.id) | \($0.title)" }.joined(separator: "\n")
                var incomplete: [String: String] = [:]
                if !actionLines.hasSameUTF8(as: originalLines) {
                    let lines = actionLines.split(whereSeparator: \.isNewline)
                    value.actions = lines.compactMap { line in
                        let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                        guard parts.count == 2 else { return nil }
                        return .init(id: parts[0].trimmingCharacters(in: .whitespaces), title: parts[1].trimmingCharacters(in: .whitespaces))
                    }
                    if value.actions.count != lines.count { incomplete["actions"] = actionLines }
                }
                if let options = try? JSONDecoder().decode([ScriptOption].self, from: Data(optionsJSON.utf8)) {
                    value.options = options.isEmpty && definition.options == nil ? nil : options
                } else { incomplete["options"] = optionsJSON }
                value.capabilities = allowsClipboardWrite ? ["clipboard.write"] : []
                if !regenerateTitle.hasSameUTF8(as: definition.regenerateTitle ?? "") {
                    let label = regenerateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.regenerateTitle = label.isEmpty ? nil : label
                }

                let text = try original?.scriptText(for: value) ?? ToolScriptDocument.text(for: value)
                guard !incomplete.isEmpty else { return text }
                let document = try ToolScriptDocument(text: text)
                guard var metadata = try JSONSerialization.jsonObject(with: document.metadata) as? [String: Any] else {
                    throw ToolDiagnostic("The recovered tool header must be a JSON object.")
                }
                for (key, partial) in incomplete { metadata[key] = partial }
                let recovered = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                return try ToolScriptDocument.text(metadata: recovered, source: value.source)
            }
        }
    }
}
