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
        for url in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let definition = try PortableToolFile(reading: url).definition
                guard url.lastPathComponent == "\(definition.id).json" else {
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
        let document = try PortableToolFile(reading: directoryURL.appendingPathComponent("\(id).json"))
        guard document.definition.id == id else { throw Error.updateConflict(id) }
        return document
    }

    /// The expected version is the previous local file. A nil version requires
    /// the destination to be absent, including when installing a first override.
    /// An unchanged signed definition needs no local file or future migration.
    @discardableResult
    func save(_ definition: ScriptToolDefinition, replacing expected: ScriptToolDefinition?,
              preserving original: PortableToolFile? = nil) throws -> Bool {
        try Self.validateID(definition.id)
        try definition.validate()
        if let expected, expected.id != definition.id { throw Error.updateConflict(definition.id) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var wroteFile = false
        try coordinate(definition.id, options: .forReplacing) { target in
            var source = original
            if let expected {
                source = try self.checkedDocument(at: target, expecting: expected)
            } else if try Self.hasItem(at: target) {
                throw Error.createConflict(definition.id)
            } else if let bundled = CustomToolCatalog.bundledByID[definition.id] {
                let canonical = try PortableToolFile.encode(bundled)
                if try canonical == PortableToolFile.encode(definition) {
                    guard let original else { return }
                    // Imported tools may add fields this version cannot edit.
                    let proposed = try PortableToolFile(data: original.data(for: definition))
                    if try proposed.hasSameContent(as: PortableToolFile(data: canonical)) { return }
                }
            }
            try PortableToolFile.export(definition, preserving: source, to: target)
            wroteFile = true
        }
        return wroteFile
    }

    func removeBuiltInOverride(replacing expected: ScriptToolDefinition, original: PortableToolFile) throws {
        guard CustomToolCatalog.bundledByID[expected.id] != nil else { throw Error.invalidID(expected.id) }
        try coordinate(expected.id, options: .forDeleting) { target in
            let stored = try self.checkedDocument(at: target, expecting: expected)
            // Restore deletes the entire document, including unknown metadata.
            if try !stored.hasSameContent(as: original) { throw Error.updateConflict(expected.id) }
            try FileManager.default.removeItem(at: target)
        }
    }

    private func checkedDocument(at target: URL, expecting expected: ScriptToolDefinition) throws -> PortableToolFile {
        guard try Self.hasItem(at: target) else { throw Error.updateConflict(expected.id) }
        let stored = try PortableToolFile(reading: target)
        guard try PortableToolFile.encode(stored.definition) == PortableToolFile.encode(expected) else {
            throw Error.updateConflict(expected.id)
        }
        return stored
    }

    private func coordinate(_ id: String, options: NSFileCoordinator.WritingOptions, operation: (URL) throws -> Void) throws {
        let url = directoryURL.appendingPathComponent("\(id).json")
        var coordinationError: NSError?
        var operationError: (any Swift.Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
            do { try operation(target) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
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
