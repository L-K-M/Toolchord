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
            case .invalidID: return "Use a custom. identifier followed by up to 80 letters, digits, hyphens or underscores."
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
                let definition = try read(url)
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

    func save(_ definition: ScriptToolDefinition, replacing expected: ScriptToolDefinition?) throws {
        try Self.validateID(definition.id)
        try definition.validate()
        if let expected, expected.id != definition.id { throw Error.updateConflict(definition.id) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("\(definition.id).json")
        let data = try Self.encode(definition)
        var coordinationError: NSError?
        var writeError: (any Swift.Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                if let expected {
                    guard FileManager.default.fileExists(atPath: target.path),
                          try Self.encode(read(target)) == Self.encode(expected) else {
                        throw Error.updateConflict(definition.id)
                    }
                } else if FileManager.default.fileExists(atPath: target.path) {
                    throw Error.createConflict(definition.id)
                }
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func read(_ url: URL) throws -> ScriptToolDefinition {
        do {
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
                throw ToolDiagnostic("Use a regular JSON document, not a directory or symbolic link.")
            }
            guard (metadata.fileSize ?? 0) <= 1024 * 1024 else { throw ToolDiagnostic("The tool document exceeds 1 MiB.") }
            let definition = try JSONDecoder().decode(ScriptToolDefinition.self, from: Data(contentsOf: url))
            try Self.validateID(definition.id)
            try definition.validate()
            return definition
        } catch {
            let message = (error as? ToolDiagnostic)?.description ?? error.localizedDescription
            throw Error.document(url.lastPathComponent, message)
        }
    }

    private static func validateID(_ id: String) throws {
        let suffix = id.dropFirst(7)
        guard id.hasPrefix("custom."), !suffix.isEmpty, suffix.utf8.count <= 80,
              suffix.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw Error.invalidID(id)
        }
    }

    private static func encode(_ definition: ScriptToolDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(definition)
    }
}
