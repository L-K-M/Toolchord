import Foundation

/// A JavaScript program with a JSON metadata comment at the beginning of the file.
/// Reading the header never executes or parses the body, so an author can repair a draft.
public struct ToolScriptDocument {
    public static let byteLimit = 1024 * 1024
    private static let marker = "/* @toolchord"
    public let definition: ScriptToolDefinition
    public let metadata: Data

    public init(text: String) throws {
        guard text.utf8.count <= Self.byteLimit else { throw ScriptFailure("The tool document exceeds 1 MiB.") }
        var contents = text[...]
        if contents.first == "\u{feff}" { contents = contents.dropFirst() }
        guard contents.hasPrefix(Self.marker) else {
            throw ScriptFailure("Start the script with a /* @toolchord metadata comment.")
        }
        contents = contents.dropFirst(Self.marker.count)
        guard Self.removeLineEnding(from: &contents), let end = contents.range(of: "*/", options: .literal) else {
            throw ScriptFailure("Put JSON on the lines after /* @toolchord and close the comment with */.")
        }
        metadata = Data(contents[..<end.lowerBound].utf8)
        contents = contents[end.upperBound...]
        guard contents.isEmpty || Self.removeLineEnding(from: &contents) else {
            throw ScriptFailure("Start the JavaScript body on the line after */.")
        }
        var object = try Self.metadataObject(metadata)
        object["summary"] = object["summary"] ?? ""
        object["actions"] = object["actions"] ?? []
        object["capabilities"] = object["capabilities"] ?? []
        object["source"] = ""
        do {
            var decoded = try JSONDecoder().decode(ScriptToolDefinition.self, from: JSONSerialization.data(withJSONObject: object))
            decoded.source = String(contents)
            definition = decoded
        } catch let DecodingError.keyNotFound(key, _) {
            throw ScriptFailure("The tool metadata is missing \"\(key.stringValue)\".")
        } catch DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context) {
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw ScriptFailure("Check the value of the tool metadata field \"\(field)\".")
        } catch {
            throw ScriptFailure("Check the tool metadata. " + error.localizedDescription)
        }
    }

    public static func text(for definition: ScriptToolDefinition) throws -> String {
        var headerFields = definition
        headerFields.source = ""
        let data = try JSONEncoder().encode(headerFields)
        guard var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScriptFailure("Tool metadata must be a JSON object.")
        }
        fields.removeValue(forKey: "source")
        let header = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        return try text(metadata: header, source: definition.source)
    }

    public static func text(metadata: Data, source: String) throws -> String {
        _ = try metadataObject(metadata)
        // A valid JSON string can contain the JavaScript block-comment terminator.
        // Escape its slash as JSON so the header can never introduce executable code.
        guard let header = String(data: metadata, encoding: .utf8) else {
            throw ScriptFailure("Use UTF-8 for the tool metadata.")
        }
        return marker + "\n" + header.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "*/", with: "*\\/") + "\n*/\n" + source
    }

    private static func metadataObject(_ data: Data) throws -> [String: Any] {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data) }
        catch { throw ScriptFailure("Check the JSON in the tool metadata comment. " + error.localizedDescription) }
        guard let object = value as? [String: Any] else { throw ScriptFailure("Tool metadata must be a JSON object.") }
        guard object["source"] == nil else { throw ScriptFailure("Place the JavaScript source below the metadata comment.") }
        return object
    }

    private static func removeLineEnding(from contents: inout Substring) -> Bool {
        guard let first = contents.first, first == "\n" || first == "\r\n" || first == "\r" else { return false }
        contents = contents.dropFirst()
        return true
    }
}
