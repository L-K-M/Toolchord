import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct BundledToolLibraryTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    @Test func browsingAndSavingAnUnchangedBuiltInDoesNotInstallAnOverride() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let library = CustomToolLibrary(store: store)
        #expect(library.reload())
        #expect(library.definitions.map(\.id).sorted() == ToolCatalog.commands.map(\.id).sorted())
        let original = try library.document(for: "json.format")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        try library.save(original.definition, replacing: original.definition, preserving: original)
        #expect(try store.load().isEmpty)
        #expect(!library.isModifiedBuiltIn(id: original.definition.id))
    }

    @Test func localEditReplacesOnePaletteCommandAndRestoringSurvivesRelaunch() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let first = CustomToolLibrary(store: store)
        let original = try first.document(for: "json.format").definition
        let custom = ScriptToolDefinition(id: "custom.sibling", title: "Sibling", source: "function preview(input) { return input; }")
        try first.save(custom, replacing: nil)
        var edited = original
        edited.title = "My Formatter"
        edited.source = "function preview(input) { return 'edited ' + input; }"
        try first.save(edited, replacing: original)

        let reloaded = CustomToolLibrary(store: store)
        var palette: [ToolCommand] = []
        reloaded.onChange = { palette = $0 }
        #expect(reloaded.reload())
        #expect(palette.map(\.id) == ToolCatalog.commands.map(\.id) + [CustomToolCatalog.makerID, custom.id])
        #expect(reloaded.definitions.filter { $0.id == edited.id } == [edited])
        let request = ToolRequest(input: .text(#"{"x":1}"#))
        let override = try #require(palette.first { $0.id == edited.id })
        #expect(override.title == edited.title)
        #expect(override.run(request).output?.primaryText == #"edited {"x":1}"#)
        #expect(reloaded.isModifiedBuiltIn(id: edited.id))

        try reloaded.restoreBuiltIn(replacing: edited, original: reloaded.document(for: edited.id))
        #expect(!reloaded.isModifiedBuiltIn(id: edited.id))
        #expect(try store.load() == [custom])
        #expect(try reloaded.document(for: edited.id).definition == original)
        let restored = try #require(palette.first { $0.id == edited.id })
        #expect(restored.title == original.title)
        #expect(restored.run(request).output?.primaryText == "{\n  \"x\": 1\n}")
        #expect(reloaded.reload())
        #expect(!reloaded.isModifiedBuiltIn(id: edited.id))
    }

    @Test func reloadDetectsByteChangesInCanonicallyEquivalentScripts() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let library = CustomToolLibrary(store: store)
        let bundled = try library.document(for: "json.format").definition
        var first = bundled
        first.source = "function preview() { return String('é'.length); }"
        var palette: [ToolCommand] = []
        library.onChange = { palette = $0 }
        try library.save(first, replacing: bundled)
        let before = try #require(palette.first { $0.id == bundled.id })
        #expect(before.run(ToolRequest(input: .text("x"))).output?.primaryText == "1")
        var second = first
        second.source = first.source.decomposedStringWithCanonicalMapping
        try store.save(second, replacing: first)
        #expect(library.reload())
        let after = try #require(palette.first { $0.id == bundled.id })
        #expect(after.run(ToolRequest(input: .text("x"))).output?.primaryText == "2")
    }

    @Test func independentLibrariesRejectStaleFirstSavesUpdatesAndRestores() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let first = CustomToolLibrary(store: store)
        let second = CustomToolLibrary(store: store)
        let signed = try first.document(for: "json.format").definition
        var one = signed
        one.title = "First"
        try first.save(one, replacing: signed)
        var two = signed
        two.title = "Second"
        #expect(throws: ScriptToolStore.Error.createConflict(one.id)) { try second.save(two, replacing: signed) }
        #expect(second.reload())
        let previousFile = try second.document(for: one.id)
        try first.save(two, replacing: one)
        #expect(throws: ScriptToolStore.Error.updateConflict(one.id)) { try second.save(signed, replacing: one) }
        #expect(throws: ScriptToolStore.Error.updateConflict(one.id)) { try second.restoreBuiltIn(replacing: one, original: previousFile) }
        #expect(try store.load() == [two])
        try first.restoreBuiltIn(replacing: two, original: first.document(for: two.id))
        #expect(throws: ScriptToolStore.Error.updateConflict(one.id)) { try second.save(signed, replacing: one) }
        #expect(try store.load().isEmpty)
    }

    @Test func extensionOnlyOverrideIsPreservedAndStaleRestoreCannotDeleteNewMetadata() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let library = CustomToolLibrary(store: store)
        let bundled = try library.document(for: "json.format")
        var metadata = try #require(JSONSerialization.jsonObject(with: bundled.original) as? [String: Any])
        metadata["x-owner"] = "first"
        let imported = try PortableToolFile(data: JSONSerialization.data(withJSONObject: metadata))
        try library.save(bundled.definition, replacing: bundled.definition, preserving: imported)
        #expect(library.isModifiedBuiltIn(id: bundled.definition.id))
        let file = folder.appendingPathComponent("json.format.json")
        #expect(try Data(contentsOf: file) == imported.original)
        metadata["x-owner"] = "second"
        let newer = try JSONSerialization.data(withJSONObject: metadata)
        try newer.write(to: file)
        #expect(throws: ScriptToolStore.Error.updateConflict(bundled.definition.id)) {
            try library.restoreBuiltIn(replacing: bundled.definition, original: imported)
        }
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test func corruptOverrideFallsBackWithoutDamagingItsFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = folder.appendingPathComponent("json.format.json")
        let damaged = Data("broken".utf8)
        try damaged.write(to: file)
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        #expect(library.reload())
        #expect(library.loadProblem?.contains("json.format.json") == true)
        let original = try library.document(for: "json.format").definition
        #expect(!library.isModifiedBuiltIn(id: original.id))
        var changed = original
        changed.title = "New title"
        #expect(throws: ScriptToolStore.Error.createConflict(original.id)) { try library.save(changed, replacing: original) }
        #expect(try Data(contentsOf: file) == damaged)
    }
}
