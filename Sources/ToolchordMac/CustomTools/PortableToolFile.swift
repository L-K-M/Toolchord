import Foundation
import ToolchordCore

/// Keeps a v1 tool's original representation for lossless Open/Export, including
/// any extension fields an older Toolchord does not understand.
struct PortableToolFile {
    static let byteLimit = 1024 * 1024
    let definition: ScriptToolDefinition
    let original: Data

    init(data: Data) throws {
        guard data.count <= Self.byteLimit else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
        definition = try JSONDecoder().decode(ScriptToolDefinition.self, from: data)
        try definition.validate()
        original = data
    }

    init(reading url: URL) throws {
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
        } catch {
            let message = (error as? ToolDiagnostic)?.description ?? error.localizedDescription
            throw ScriptToolStore.Error.document(url.lastPathComponent, message)
        }
    }

    func hasSameContent(as other: Self) throws -> Bool {
        if original == other.original { return true }
        func normalized(_ data: Data) throws -> Data {
            try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: .sortedKeys)
        }
        return try normalized(original) == normalized(other.original)
    }

    func data(for current: ScriptToolDefinition) throws -> Data {
        let before = try Self.encode(definition)
        let after = try Self.encode(current)
        guard before != after else { return original }

        guard let document = try JSONSerialization.jsonObject(with: original) as? JSONObject,
              let previous = try JSONSerialization.jsonObject(with: before) as? JSONObject,
              let edited = try JSONSerialization.jsonObject(with: after) as? JSONObject else {
            throw ToolDiagnostic("The tool document must contain a JSON object.")
        }
        let merged = try Self.merge(original: document, previous: previous, edited: edited)
        return try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys, .prettyPrinted])
    }

    private typealias JSONObject = [String: Any]

    private static func merge(original: JSONObject, previous before: JSONObject, edited after: JSONObject) throws -> JSONObject {
        var result = original
        for key in Set(before.keys).union(after.keys) {
            guard try fieldBytes(before[key]) != fieldBytes(after[key]) else { continue }
            if let rows = original[key] as? [JSONObject],
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
        let bytes = try original?.data(for: definition) ?? encode(definition)
        guard bytes.count <= byteLimit else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try bytes.write(to: url, options: .atomic)
    }
}
