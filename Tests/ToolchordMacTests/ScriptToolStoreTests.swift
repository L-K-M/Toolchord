import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@Suite struct ScriptToolStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ScriptToolStoreTests-\(UUID().uuidString)")
    }

    private func definition(id: String = "custom.test", title: String = "Trim Text") -> ScriptToolDefinition {
        ScriptToolDefinition(id: id, title: title, source: "function preview(input) { return input.trim(); }")
    }

    @Test func createReloadAndUpdateKeepOneStableDocument() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        #expect(try store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let original = definition()
        try store.save(original, replacing: nil)
        #expect(try store.load() == [original])
        var updated = original
        updated.title = "Trim Lines"
        try store.save(updated, replacing: original)
        #expect(try store.load() == [updated])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["custom.test.json"])
    }

    @Test func createAndStaleUpdatesNeverClobberExistingDocument() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        let original = definition()
        try store.save(original, replacing: nil)
        #expect(throws: ScriptToolStore.Error.createConflict(original.id)) { try store.save(original, replacing: nil) }
        var newer = original
        newer.title = "Newer Tool"
        try store.save(newer, replacing: original)
        #expect(throws: ScriptToolStore.Error.updateConflict(original.id)) { try store.save(original, replacing: original) }
        #expect(try store.load() == [newer])
    }

    @Test func expectedVersionCanHaveDifferentJSONFormatting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        let original = definition()
        try store.save(original, replacing: nil)
        let compact = try JSONEncoder().encode(original)
        try compact.write(to: directory.appendingPathComponent("custom.test.json"))
        var updated = original
        updated.summary = "Updated description"
        try store.save(updated, replacing: original)
        #expect(try store.load() == [updated])
    }

    @Test func invalidAndMismatchedDocumentsAreReported() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("custom.other.json")
        try Data("not JSON".utf8).write(to: url)
        var report = try store.loadWithDiagnostics()
        #expect(report.definitions.isEmpty)
        #expect(report.problems.first?.contains("custom.other.json") == true)
        try JSONEncoder().encode(definition()).write(to: url)
        report = try store.loadWithDiagnostics()
        #expect(report.definitions.isEmpty)
        #expect(report.problems.first?.contains("filename") == true)
    }

    @Test func unsafeAndBuiltInIDsAndInvalidSourceAreRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        for id in ["", "json.format", "custom../escape", "custom.a/b", "custom.a.b"] {
            #expect(throws: ScriptToolStore.Error.invalidID(id)) { try store.save(definition(id: id), replacing: nil) }
        }
        var invalid = definition()
        invalid.source = "function {"
        #expect(throws: (any Error).self) { try store.save(invalid, replacing: nil) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func inaccessibleDirectoryIsNotReportedAsAnEmptyLibrary() throws {
        let file = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("file".utf8).write(to: file)
        #expect(throws: (any Error).self) { _ = try ScriptToolStore(directoryURL: file).load() }
    }

    @Test @MainActor func damagedDocumentDoesNotHideValidToolsOrGetOverwritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        let valid = definition(id: "custom.valid")
        try store.save(valid, replacing: nil)
        let damagedURL = directory.appendingPathComponent("custom.damaged.json")
        let damaged = Data("malformed JSON".utf8)
        try damaged.write(to: damagedURL)
        let library = CustomToolLibrary(store: store)
        var catalog: [ToolCommand] = []
        library.onChange = { catalog = $0 }
        #expect(library.reload())
        #expect(library.definitions == [valid])
        #expect(catalog.contains { $0.id == valid.id })
        #expect(library.loadProblem?.contains("custom.damaged.json") == true)
        var updated = valid
        updated.title = "Updated Valid Tool"
        try library.save(updated, replacing: valid)
        #expect(try store.load() == [updated])
        #expect(try Data(contentsOf: damagedURL) == damaged)
    }
}
