import Foundation
import ToolchordCore

/// Retains the original bytes and extension metadata across JS and legacy JSON exports.
struct PortableToolFile {
    static let byteLimit = ToolScriptDocument.byteLimit
    let definition: ScriptToolDefinition
    let original: Data
    private let scriptMetadata: Data?

    /// Header-only parsing lets a provider revise a draft whose JavaScript is incomplete.
    init(scriptText: String) throws {
        let script = try ToolScriptDocument(text: scriptText)
        definition = script.definition
        original = Data(scriptText.utf8)
        scriptMetadata = script.metadata
    }

    init(data: Data) throws {
        guard data.count <= Self.byteLimit else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolDiagnostic("Use UTF-8 for the tool document.")
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))).hasPrefix("{") {
            // Foundation consumes an opening byte-order mark during UTF-8 validation.
            // Decode the validated bytes verbatim for the editable file.
            self = try Self(scriptText: String(decoding: data, as: UTF8.self))
        } else {
            definition = try JSONDecoder().decode(ScriptToolDefinition.self, from: data)
            original = data
            scriptMetadata = nil
        }
        try definition.validate()
    }

    enum Location { case portable, installed }

    init(reading url: URL, location: Location = .portable) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
                throw ToolDiagnostic("Choose a regular tool file.")
            }
            guard (metadata.fileSize ?? 0) <= Self.byteLimit else {
                throw ToolDiagnostic("The tool document exceeds 1 MiB.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: Self.byteLimit + 1) ?? Data()
            try self.init(data: bytes)
            if location == .portable, url.pathExtension.lowercased() == "js", scriptMetadata == nil {
                throw ToolDiagnostic("A .js tool needs a /* @toolchord metadata comment and a JavaScript body.")
            }
        } catch {
            let message = (error as? ToolDiagnostic)?.description ?? error.localizedDescription
            throw ScriptToolStore.Error.document(url.lastPathComponent, message)
        }
    }

    func hasSameContent(as other: Self) throws -> Bool {
        if original == other.original { return true }
        return try Self.fieldBytes(documentObject()) == Self.fieldBytes(other.documentObject())
    }

    /// Compare the exact authored file when both sides have one. Legacy JSON
    /// can represent the equivalent JS document using a different layout.
    func matchesVersion(of other: Self) throws -> Bool {
        if scriptMetadata != nil && other.scriptMetadata != nil { return original == other.original }
        return try hasSameContent(as: other)
    }

    private func documentObject() throws -> JSONObject {
        guard var object = try JSONSerialization.jsonObject(with: scriptMetadata ?? original) as? JSONObject else {
            throw ToolDiagnostic("The tool metadata must contain a JSON object.")
        }
        if scriptMetadata != nil {
            // JS permits omitting these default fields. Legacy files require them.
            object["summary"] = definition.summary
            object["actions"] = object["actions"] ?? []
            object["capabilities"] = object["capabilities"] ?? []
            object["source"] = definition.source
        }
        return object
    }

    func scriptText(for current: ScriptToolDefinition) throws -> String {
        if scriptMetadata != nil {
            var previousHeader = definition
            var newHeader = current
            previousHeader.source = ""
            newHeader.source = ""
            if try Self.encode(previousHeader) == Self.encode(newHeader) {
                let prefix = String(decoding: original.dropLast(definition.source.utf8.count), as: UTF8.self)
                let separator = prefix.hasSuffix("*/") && !current.source.isEmpty ? "\n" : ""
                return prefix + separator + current.source
            }
        }
        var metadata = try object(for: current)
        metadata.removeValue(forKey: "source")
        let bytes = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        return try ToolScriptDocument.text(metadata: bytes, source: current.source)
    }

    /// Legacy JSON remains an explicit export format. Unchanged legacy files
    /// retain their exact original representation when re-exported as JSON.
    func data(for current: ScriptToolDefinition) throws -> Data {
        if scriptMetadata == nil, try Self.encode(definition) == Self.encode(current) { return original }
        return try JSONSerialization.data(withJSONObject: object(for: current), options: [.sortedKeys, .prettyPrinted])
    }

    private func object(for current: ScriptToolDefinition) throws -> JSONObject {
        let document = try documentObject()
        let before = try Self.encode(definition)
        let after = try Self.encode(current)
        if before == after { return document }
        guard let previous = try JSONSerialization.jsonObject(with: before) as? JSONObject,
              let edited = try JSONSerialization.jsonObject(with: after) as? JSONObject else {
            throw ToolDiagnostic("The tool metadata must contain a JSON object.")
        }
        return try Self.merge(original: document, previous: previous, edited: edited)
    }

    private typealias JSONObject = [String: Any]

    private static func merge(original: JSONObject, previous before: JSONObject, edited after: JSONObject) throws -> JSONObject {
        var result = original
        for key in Set(before.keys).union(after.keys) {
            guard try fieldBytes(before[key]) != fieldBytes(after[key]) else { continue }
            if let object = original[key] as? JSONObject, let previous = before[key] as? JSONObject,
               let edited = after[key] as? JSONObject {
                result[key] = try merge(original: object, previous: previous, edited: edited)
            } else if let rows = original[key] as? [JSONObject],
               let oldRows = before[key] as? [JSONObject],
               let newRows = after[key] as? [JSONObject] {
                // Actions, options and choices each identify their own members.
                // Follow the edited order. A new ID starts without the removed
                // item's extensions, even when it occupies the same position.
                result[key] = try newRows.map { row in
                    guard let id = row["id"] as? String,
                          let source = rows.first(where: { ($0["id"] as? String)?.hasSameUTF8(as: id) == true }),
                          let prior = oldRows.first(where: { ($0["id"] as? String)?.hasSameUTF8(as: id) == true }) else {
                        return row
                    }
                    return try merge(original: source, previous: prior, edited: row)
                }
            } else {
                result[key] = after[key]
            }
        }
        return result
    }

    // Compare encoded fields because Foundation string equality folds some
    // distinct UTF-8 spellings that an explicit edit may intend to change.
    private static func fieldBytes(_ value: Any?) throws -> Data? {
        try value.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]) }
    }

    static func encode(_ definition: ScriptToolDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(definition)
    }

    static func export(_ definition: ScriptToolDefinition, preserving original: Self?, to url: URL) throws {
        try definition.validate()
        let bytes: Data
        if url.pathExtension.lowercased() == "js" {
            bytes = try scriptData(for: definition, preserving: original)
        } else {
            bytes = try original?.data(for: definition) ?? encode(definition)
        }
        guard bytes.count <= byteLimit else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try bytes.write(to: url, options: .atomic)
    }

    static func scriptData(for definition: ScriptToolDefinition, preserving original: Self?) throws -> Data {
        let text = try original?.scriptText(for: definition) ?? ToolScriptDocument.text(for: definition)
        let bytes = Data(text.utf8)
        guard bytes.count <= byteLimit else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
        return bytes
    }
}
