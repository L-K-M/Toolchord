import Foundation
import ToolchordCore

/// Each saved tool is a separate local document. File coordination makes the
/// expected-version check and atomic replacement one operation for app writers.
final class ScriptToolStore {
    enum Error: Swift.Error, LocalizedError, Equatable {
        case document(String, String)
        case createConflict(String)
        case updateConflict(String)
        case invalidID(String)

        var errorDescription: String? {
            switch self {
            case .document(let file, let reason): return "Custom tool \(file): \(reason)"
            case .createConflict(let id): return "Custom tool \(id) already exists. Reload before saving."
            case .updateConflict(let id): return "Custom tool \(id) changed since you opened it. Reload before saving."
            case .invalidID: return "Choose a built-in tool or use a custom. identifier followed by up to 80 letters, digits, hyphens or underscores."
            }
        }
    }

    let directoryURL: URL

    struct LoadReport {
        let definitions: [ScriptToolDefinition]
        let problems: [String]
    }

    init(directoryURL: URL) { self.directoryURL = directoryURL }

    convenience init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        self.init(directoryURL: support.appendingPathComponent("Toolchord/Custom Tools", isDirectory: true))
    }

    func load() throws -> [ScriptToolDefinition] {
        try loadWithDiagnostics().definitions
    }

    func loadWithDiagnostics() throws -> LoadReport {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        } catch {
            let problem = error as NSError
            if problem.domain == NSCocoaErrorDomain,
               [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(problem.code) {
                return LoadReport(definitions: [], problems: [])
            }
            throw error
        }
        var definitions: [ScriptToolDefinition] = []
        var problems: [String] = []
        let documents = entries.filter { ["js", "json"].contains($0.pathExtension) }
        let grouped = Dictionary(grouping: documents) { $0.deletingPathExtension().lastPathComponent }
        for (name, files) in grouped.sorted(by: { $0.key < $1.key }) {
            do {
                guard files.count == 1, let url = files.first else { throw Self.duplicateFiles(name) }
                let definition = try PortableToolFile(reading: url, location: .installed).definition
                guard name.hasSameUTF8(as: definition.id) else {
                    throw Error.document(url.lastPathComponent, "The filename must match the saved tool identifier.")
                }
                definitions.append(definition)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        definitions.sort { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return LoadReport(definitions: definitions, problems: problems)
    }

    func document(for id: String) throws -> PortableToolFile {
        try Self.validateID(id)
        let url = try Self.installationURL(id, script: directoryURL.appendingPathComponent("\(id).js"),
                                          legacy: directoryURL.appendingPathComponent("\(id).json"))
        let document = try PortableToolFile(reading: url, location: .installed)
        guard document.definition.id == id else { throw Error.updateConflict(id) }
        return document
    }

    /// The expected version is the previous local file. A nil version requires
    /// the destination to be absent, including when installing a first override.
    /// An unchanged signed definition needs no local file or future migration.
    @discardableResult
    func save(_ definition: ScriptToolDefinition, replacing expected: ScriptToolDefinition?,
              preserving original: PortableToolFile? = nil, edited: PortableToolFile? = nil) throws -> Bool {
        try Self.validateID(definition.id)
        try definition.validate()
        if let expected, expected.id != definition.id { throw Error.updateConflict(definition.id) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let edited, try PortableToolFile.encode(edited.definition) != PortableToolFile.encode(definition) {
            throw Error.document(definition.id, "The script no longer matches the tested tool.")
        }
        var wroteFile = false
        try coordinate(definition.id, options: .forReplacing) { target, script in
            var source = edited ?? original
            if let expected {
                let stored = try self.checkedDocument(at: target, expecting: expected)
                if edited != nil {
                    // The raw header owns unknown fields too. Do not replace an external
                    // extension-only change with the editor's older snapshot.
                    guard let original, try stored.matchesVersion(of: original) else {
                        throw Error.updateConflict(definition.id)
                    }
                } else {
                    source = stored
                }
            } else if try Self.hasItem(at: target) {
                throw Error.createConflict(definition.id)
            }
            let bytes = try PortableToolFile.scriptData(for: definition, preserving: source)
            if expected == nil, let text = ToolCatalog.bundledScriptText(id: definition.id) {
                if edited != nil {
                    if bytes.elementsEqual(text.utf8) { return }
                } else {
                    let proposed = try PortableToolFile(scriptText: String(decoding: bytes, as: UTF8.self))
                    if try proposed.hasSameContent(as: PortableToolFile(scriptText: text)) { return }
                }
            }
            // Rename within the directory before atomically replacing its contents.
            // An interrupted migration leaves one readable copy of the old version.
            if target != script { try FileManager.default.moveItem(at: target, to: script) }
            try bytes.write(to: script, options: .atomic)
            wroteFile = true
        }
        return wroteFile
    }

    func removeBuiltInOverride(replacing expected: ScriptToolDefinition, original: PortableToolFile) throws {
        guard CustomToolCatalog.bundledByID[expected.id] != nil else { throw Error.invalidID(expected.id) }
        try coordinate(expected.id, options: .forDeleting) { target, _ in
            let stored = try self.checkedDocument(at: target, expecting: expected)
            // Restore deletes the entire document, including unknown metadata.
            if try !stored.matchesVersion(of: original) { throw Error.updateConflict(expected.id) }
            try FileManager.default.removeItem(at: target)
        }
    }

    private func checkedDocument(at target: URL, expecting expected: ScriptToolDefinition) throws -> PortableToolFile {
        guard try Self.hasItem(at: target) else { throw Error.updateConflict(expected.id) }
        let stored = try PortableToolFile(reading: target, location: .installed)
        guard try PortableToolFile.encode(stored.definition) == PortableToolFile.encode(expected) else {
            throw Error.updateConflict(expected.id)
        }
        return stored
    }

    private func coordinate(_ id: String, options: NSFileCoordinator.WritingOptions, operation: (URL, URL) throws -> Void) throws {
        let script = directoryURL.appendingPathComponent("\(id).js")
        let legacy = directoryURL.appendingPathComponent("\(id).json")
        var coordinationError: NSError?
        var operationError: (any Swift.Error)?
        NSFileCoordinator().coordinate(writingItemAt: script, options: options,
                                       writingItemAt: legacy, options: options,
                                       error: &coordinationError) { script, legacy in
            do { try operation(Self.installationURL(id, script: script, legacy: legacy), script) }
            catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private static func installationURL(_ id: String, script: URL, legacy: URL) throws -> URL {
        guard try hasItem(at: legacy) else { return script }
        if try hasItem(at: script) { throw duplicateFiles(id) }
        return legacy
    }

    private static func duplicateFiles(_ id: String) -> Error {
        .document(id, "Both a .js and a .json file exist for this tool. Keep one file in the library and reload.")
    }

    /// Treat a broken symbolic link as an occupied filename too.
    private static func hasItem(at url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) {
            return false
        }
    }

    private static func validateID(_ id: String) throws {
        guard ScriptToolDefinition.isValidToolID(id) else { throw Error.invalidID(id) }
    }
}
