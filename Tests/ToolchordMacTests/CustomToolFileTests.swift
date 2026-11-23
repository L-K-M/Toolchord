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
        #expect(!library.definitions.contains { $0.id.hasPrefix("custom.") })
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

    @Test func editingReorderingAndRenamingControlsPreservesExtensionsOnlyOnRetainedIDs() throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = root.appendingPathComponent("Controls.toolchord")
        let exported = root.appendingPathComponent("Updated.toolchord")
        let raw = """
        {
          "apiVersion": 1, "id": "custom.controls", "title": "Controls", "summary": "",
          "source": "function preview(input) { return input; }", "capabilities": ["clipboard.write"],
          "actions": [
            {"id":"old","title":"Old","extra":"discard"},
            {"id":"copy","title":"Copy","extra":"keep"}
          ],
          "options": [
            {"id":"format","label":"Format","defaultValue":"a","extra":{"version":2},"choices":[
              {"id":"a","label":"A","extension":[1,2]},
              {"id":"b","label":"B","extension":[3]},
              {"id":"c","label":"C","extension":[4]}
            ]},
            {"id":"flag","label":"Flag","defaultValue":"false","extra":"toggle"},
            {"id":"removed","label":"Remove","defaultValue":"true","extra":"discard"}
          ]
        }
        """
        try Data(raw.utf8).write(to: imported)
        let editor = CustomToolEditorModel(library: library)
        try editor.openTool(from: imported)
        editor.actionLines = "copy | Copy Value\nrenamed | Old"
        editor.optionsJSON = """
        [
          {"id":"flag","label":"Renamed Flag","defaultValue":"true"},
          {"id":"format","label":"Format","defaultValue":"b","choices":[
            {"id":"b","label":"Renamed B"},{"id":"added","label":"C"},{"id":"a","label":"A"}]},
          {"id":"new","label":"Remove","defaultValue":"true"}
        ]
        """
        try editor.exportTool(to: exported)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: exported)) as? [String: Any])
        let actions = try #require(result["actions"] as? [[String: String]])
        #expect(actions == [["id": "copy", "title": "Copy Value", "extra": "keep"], ["id": "renamed", "title": "Old"]])
        let options = try #require(result["options"] as? [[String: Any]])
        #expect(options.compactMap { $0["id"] as? String } == ["flag", "format", "new"])
        #expect(options[0]["label"] as? String == "Renamed Flag")
        #expect(options[0]["extra"] as? String == "toggle")
        #expect(options[1]["extra"] as? [String: Int] == ["version": 2])
        #expect(options[2]["extra"] == nil)
        let choices = try #require(options[1]["choices"] as? [[String: Any]])
        #expect(choices.compactMap { $0["id"] as? String } == ["b", "added", "a"])
        #expect(choices[0]["label"] as? String == "Renamed B")
        #expect(choices[0]["extension"] as? [Int] == [3])
        #expect(choices[1]["extension"] == nil)
        #expect(choices[2]["extension"] as? [Int] == [1, 2])
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

    @Test func importingBuiltInCustomizationStagesRunsAndRestoresTheSameCommand() async throws {
        let (root, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = CustomToolEditorModel(library: library, editing: "json.format")
        let bundled = editor.definition
        try #require(bundled.id == "json.format")
        #expect(bundled.source.contains("function preview("))

        var customized = bundled
        customized.source = "function preview(input, options, api) { return api.id + ' ' + input; }"
        var json = try #require(try JSONSerialization.jsonObject(with: PortableToolFile.encode(customized)) as? [String: Any])
        json["extension-note"] = "preserve when installed"
        let raw = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        let url = root.appendingPathComponent("Customized.toolchord")
        try raw.write(to: url)
        try editor.openTool(from: url)
        #expect(editor.isDirty && !editor.canSave)
        #expect(!library.isModifiedBuiltIn(id: bundled.id))
        #expect(editor.expected == bundled)

        editor.sampleInput = "sample"
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "json.format sample")
        try #require(editor.save())
        #expect(try library.document(for: bundled.id).original == raw)
        let reopened = CustomToolEditorModel(library: library, editing: bundled.id)
        #expect(reopened.definition == customized)
        #expect(library.isModifiedBuiltIn(id: bundled.id))

        try PortableToolFile.encode(bundled).write(to: url)
        #expect(throws: (any Error).self) { try reopened.openTool(from: url) }
        reopened.definition.summary = "Unsaved changes"
        reopened.restoreBuiltIn()
        #expect(reopened.definition == bundled && reopened.expected == bundled)
        #expect(!reopened.isDirty && !reopened.canSave && !reopened.isError)
        #expect(!library.isModifiedBuiltIn(id: bundled.id))
        #expect(try ScriptToolStore(directoryURL: root.appendingPathComponent("Library")).load().isEmpty)
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
