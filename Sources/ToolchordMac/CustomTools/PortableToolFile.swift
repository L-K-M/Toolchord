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

        // Replace only edited schema fields. Other top-level metadata and
        // nested option metadata in unedited fields survive a normal edit.
        guard var document = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              let previous = try JSONSerialization.jsonObject(with: before) as? [String: NSObject],
              let edited = try JSONSerialization.jsonObject(with: after) as? [String: NSObject] else {
            throw ToolDiagnostic("The tool document must contain a JSON object.")
        }
        // Foundation string equality treats some distinct UTF-8 spellings
        // as equal; compare the encoded field so an explicit edit survives.
        func field(_ object: NSObject?) throws -> Data? {
            try object.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]) }
        }
        for key in Set(previous.keys).union(edited.keys) {
            if try field(previous[key]) != field(edited[key]) {
                document[key] = edited[key]
            }
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
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
