import Foundation
import Observation
import ToolchordCore

/// User documents are kept separately from the in-memory palette draft.
@MainActor
@Observable
final class CustomToolLibrary {
    private(set) var definitions: [ScriptToolDefinition] = []
    private(set) var loadProblem: String?
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
            let commands = try CustomToolCatalog.commands(for: report.definitions)
            definitions = report.definitions
            loadProblem = report.problems.isEmpty ? nil : report.problems.joined(separator: "\n")
            onChange?(commands)
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

    func document(for id: String) throws -> PortableToolFile {
        guard let store else { throw ToolDiagnostic(loadProblem ?? "Custom tool storage is unavailable.") }
        return try store.document(for: id)
    }

    func save(_ definition: ScriptToolDefinition, replacing expected: ScriptToolDefinition?,
              preserving original: PortableToolFile? = nil) throws {
        guard let store else { throw ToolDiagnostic(loadProblem ?? "Custom tool storage is unavailable.") }
        try store.save(definition, replacing: expected, preserving: original)
        // A different invalid file must not make this successful save look
        // like a failure, nor discard its immediately searchable command.
        definitions.removeAll { $0.id == definition.id }
        definitions.append(definition)
        definitions.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        onChange?(try CustomToolCatalog.commands(for: definitions))
    }
}
