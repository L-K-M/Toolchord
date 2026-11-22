import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct CustomToolFileTests {
    private let source = """
    {
      "apiVersion": 1, "id": "custom.test",
      "title": "Test Tool", "summary": "Trim",
      "source": "function preview(input) { return input.trim(); }",
      "actions": [], "capabilities": [], "options": [],
      "x-custom-metadata": { "author": "tester" }
    }

    """

    private func fixture() throws -> (directory: URL, library: CustomToolLibrary) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return (root, CustomToolLibrary(store: ScriptToolStore(directoryURL: root.appendingPathComponent("Library"))))
    }

    @Test(arguments: ["json", "toolchord"])
    func importedFilesRoundTripBeforeAndAfterInstalling(_ fileExtension: String) async throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Original").appendingPathExtension(fileExtension)
        let exported = root.appendingPathComponent("Exported.toolchord")
        let raw = Data(source.utf8)
        try raw.write(to: url)
        let editor = CustomToolEditorModel(library: library)
        try editor.openTool(from: url)
        #expect(editor.isDirty && !editor.canSave)
        #expect(editor.trialResult == nil)
        #expect(library.definitions.isEmpty)
        try editor.exportTool(to: exported)
        #expect(try Data(contentsOf: exported) == raw)
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.save())
        #expect(try Data(contentsOf: root.appendingPathComponent("Library/custom.test.json")) == raw)

        let reopened = CustomToolEditorModel(library: library, editing: "custom.test")
        try reopened.exportTool(to: exported)
        #expect(try Data(contentsOf: exported) == raw)
        reopened.definition.title = "Edited"
        try reopened.exportTool(to: exported)
        let edited = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: exported)) as? [String: Any])
        #expect(edited["title"] as? String == "Edited")
        #expect(edited["x-custom-metadata"] as? [String: String] == ["author": "tester"])
        #expect(try Data(contentsOf: url) == raw)
    }

    @Test func anImportedToolKeepsItsFileAndIdentityThroughRecoveryAndRevertUndo() throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Example.toolchord")
        let exported = root.appendingPathComponent("Recovered.toolchord")
        let original = Data(source.utf8)
        try original.write(to: file)
        let editor = CustomToolEditorModel(library: library)
        try editor.openTool(from: file)
        editor.flushRecovery()
        try FileManager.default.removeItem(at: file)
        let recovered = CustomToolEditorModel(library: library)
        try #require(recovered.restoreRecoveryIfAvailable())
        try recovered.exportTool(to: exported)
        #expect(try Data(contentsOf: exported) == original)

        recovered.definition.title = "Edited"
        recovered.revert()
        #expect(recovered.definition.id == "custom.test")
        #expect(recovered.definition.title == "Test Tool")
        #expect(recovered.isDirty && recovered.expected == nil)
        recovered.undoManager.undo()
        #expect(recovered.definition.title == "Edited")
        #expect(recovered.definition.id == "custom.test")
        #expect(recovered.isDirty && recovered.expected == nil)
        recovered.discardDraft()
    }

    @Test func matchingKnownFieldsDoNotMaskConflictingExtensionData() throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Example.toolchord")
        let installed = try JSONDecoder().decode(ScriptToolDefinition.self, from: Data(source.utf8))
        try library.save(installed, replacing: nil)
        // An identical v1 tool whose extension field only exists in the portable copy.
        try Data(source.utf8).write(to: url)
        let editor = CustomToolEditorModel(library: library, editing: installed.id)
        #expect(throws: (any Error).self) { try editor.openTool(from: url) }
        #expect(try Data(contentsOf: url) == Data(source.utf8))
    }

    @Test func failedImportKeepsTheCurrentToolAndInstalledCopy() throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = ScriptToolDefinition(id: "custom.test", title: "Installed", source: "function preview(input) { return input; }")
        try library.save(installed, replacing: nil)
        let editor = CustomToolEditorModel(library: library, editing: installed.id)
        let url = root.appendingPathComponent("Incoming.toolchord")
        let invalidInputs = ["{", source.replacingOccurrences(of: "\"apiVersion\": 1", with: "\"apiVersion\": 2"), source]
        for invalid in invalidInputs {
            try Data(invalid.utf8).write(to: url)
            #expect(throws: (any Error).self) { try editor.openTool(from: url) }
            #expect(editor.definition == installed)
        }
        #expect(try library.document(for: installed.id).definition == installed)
    }
}
