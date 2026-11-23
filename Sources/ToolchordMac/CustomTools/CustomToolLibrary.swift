import Foundation
import Observation
import ToolchordCore

/// The signed tools are always available. Local files customize a built-in
/// in place or add an independently identified tool.
@MainActor
@Observable
final class CustomToolLibrary {
    private(set) var definitions = ToolCatalog.bundledDefinitions.sorted(by: orderedByTitle)
    private(set) var loadProblem: String?
    private var installedCommands: [String: ToolCommand] = [:]
    @ObservationIgnored private let store: ScriptToolStore?
    @ObservationIgnored var onChange: (([ToolCommand]) -> Void)?

    init(store: ScriptToolStore? = nil) {
        do {
            self.store = try store ?? ScriptToolStore()
        } catch {
            self.store = nil
            loadProblem = error.localizedDescription
        }
    }

    @discardableResult
    func reload() -> Bool {
        guard let store else { return false }
        do {
            let report = try store.loadWithDiagnostics()
            let previous = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
            let installed = try Dictionary(uniqueKeysWithValues: report.definitions.map {
                ($0.id, try command(for: $0, previous: previous[$0.id]))
            })
            let defaults = ToolCatalog.bundledDefinitions.filter { installed[$0.id] == nil }
            definitions = (defaults + report.definitions).sorted(by: Self.orderedByTitle)
            installedCommands = installed
            loadProblem = report.problems.isEmpty ? nil : report.problems.joined(separator: "\n")
            onChange?(CustomToolCatalog.commands(including: installed))
            return true
        } catch {
            // Keep the last known good catalog. The authoring window exposes
            // the failing document instead of silently hiding the error.
            loadProblem = error.localizedDescription
            return false
        }
    }

    /// A private, separate file keeps partial editor metadata out of the installed catalog.
    var recoveryURL: URL? { store?.directoryURL.appendingPathComponent(".workspace/AuthoringDraft.json") }

    func isModifiedBuiltIn(id: String) -> Bool {
        CustomToolCatalog.bundledByID[id] != nil && installedCommands[id] != nil
    }

    func document(for id: String) throws -> PortableToolFile {
        if installedCommands[id] == nil, let bundled = CustomToolCatalog.bundledByID[id] {
            return try PortableToolFile(data: PortableToolFile.encode(bundled))
        }
        guard let store else { throw ToolDiagnostic(loadProblem ?? "Tool storage is unavailable.") }
        return try store.document(for: id)
    }

    func save(_ definition: ScriptToolDefinition, replacing expected: ScriptToolDefinition?,
              preserving original: PortableToolFile? = nil) throws {
        guard let store else { throw ToolDiagnostic(loadProblem ?? "Tool storage is unavailable.") }
        let localVersion: ScriptToolDefinition?
        if installedCommands[definition.id] == nil, let bundled = CustomToolCatalog.bundledByID[definition.id] {
            guard let expected else { throw ScriptToolStore.Error.createConflict(definition.id) }
            guard try PortableToolFile.encode(bundled) == PortableToolFile.encode(expected) else {
                throw ScriptToolStore.Error.updateConflict(definition.id)
            }
            localVersion = nil
        } else {
            localVersion = expected
        }
        let command = try command(for: definition, previous: definitions.first { $0.id == definition.id })
        guard try store.save(definition, replacing: localVersion, preserving: original) else { return }
        installedCommands[definition.id] = command
        publish(definition)
    }

    func restoreBuiltIn(replacing expected: ScriptToolDefinition, original: PortableToolFile) throws {
        guard let store else { throw ToolDiagnostic(loadProblem ?? "Tool storage is unavailable.") }
        guard let bundled = CustomToolCatalog.bundledByID[expected.id] else { throw ScriptToolStore.Error.invalidID(expected.id) }
        try store.removeBuiltInOverride(replacing: expected, original: original)
        installedCommands.removeValue(forKey: expected.id)
        publish(bundled)
    }

    /// Keep an unchanged command instance and its active generator seed when the
    /// workspace reopens. JavaScript can distinguish canonically equal strings.
    private func command(for definition: ScriptToolDefinition, previous: ScriptToolDefinition?) throws -> ToolCommand {
        if let cached = installedCommands[definition.id], let previous,
           try PortableToolFile.encode(previous) == PortableToolFile.encode(definition) {
            return cached
        }
        return try definition.command()
    }

    private func publish(_ definition: ScriptToolDefinition) {
        definitions.removeAll { $0.id == definition.id }
        definitions.append(definition)
        definitions.sort(by: Self.orderedByTitle)
        onChange?(CustomToolCatalog.commands(including: installedCommands))
    }

    nonisolated private static func orderedByTitle(_ lhs: ScriptToolDefinition, _ rhs: ScriptToolDefinition) -> Bool {
        let order = lhs.title.localizedStandardCompare(rhs.title)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
}
