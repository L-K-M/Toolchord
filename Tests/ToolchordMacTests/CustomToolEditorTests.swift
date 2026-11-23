import AppKit
import Foundation
import SwiftUI
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct CustomToolEditorTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CustomToolEditorTests-\(UUID().uuidString)")
    }

    @Test func manualDraftMustPassItsCurrentSampleBeforeSaving() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, generator: UnavailableGenerator())
        editor.sampleInput = " hello "
        editor.save()
        #expect(!library.definitions.contains { $0.id.hasPrefix("custom.") })
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "hello")
        #expect(editor.canSave)

        editor.scriptText = editor.scriptText.replacingOccurrences(of: "Trim Text", with: "Trim My Text")
        #expect(!editor.canSave)
        editor.runSample()
        await editor.waitForIdle()
        editor.save()
        #expect(!editor.isError)
        #expect(!editor.isDirty)
        let persisted = try ScriptToolStore(directoryURL: folder).load()
        #expect(persisted.count == 1)
        #expect(persisted[0].title == "Trim My Text")

        let fileURL = folder.appendingPathComponent("\(persisted[0].id).js")
        let bytes = try Data(contentsOf: fileURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(" hello "))
    }

    @Test func generationKeepsIdentityAndUpdatingKeepsOneDocument() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        var original = ScriptToolDefinition(id: "custom.original", title: "Lowercase", source: "function preview(input) { return input.toLowerCase(); }")
        original.options = try JSONDecoder().decode([ScriptOption].self, from: Data(#"[{"id":"extra","label":"Extra","defaultValue":"false"}]"#.utf8))
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let generated = ScriptToolDefinition(id: "custom.wrong", title: "Uppercase", source: "function preview(input) { return input.toUpperCase(); }")
        let editor = CustomToolEditorModel(library: library, generator: FixedGenerator(definition: generated), editing: original.id)
        editor.description = "Uppercase the input"
        editor.generate()
        await editor.waitForIdle()
        #expect(editor.definition.id == original.id)
        editor.sampleInput = "Hello"
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "HELLO")
        editor.save()
        #expect(!editor.isError)
        let documents = try store.load()
        #expect(documents.count == 1)
        #expect(documents[0].id == original.id)
        #expect(documents[0].title == "Uppercase")
    }

    @Test func manualEditingPreservesOptionsAndGeneratorMetadata() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        var current = ScriptToolDefinition(id: "custom.original", title: "Generate", source: "function preview(input, options, api) { return api.seed; }")
        current.options = try JSONDecoder().decode([ScriptOption].self, from: Data(#"[{"id":"upper","label":"Uppercase","defaultValue":"false"}]"#.utf8))
        current.regenerateTitle = "Generate Again"
        try store.save(current, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let editor = CustomToolEditorModel(library: library, generator: UnavailableGenerator(), editing: current.id)

        var edited = editor.definition
        edited.summary = "Updated summary"
        editor.scriptText = try ToolScriptDocument.text(for: edited)
        editor.runSample()
        await editor.waitForIdle()
        try #require(editor.canSave)
        editor.save()
        let saved = try #require(try store.load().first)
        #expect(saved.options == current.options)
        #expect(saved.regenerateTitle == "Generate Again")
        #expect(saved.id == current.id)
    }

    @Test func generatorTrialsReceiveSeedsAndOptionChangesInvalidateTrial() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, generator: UnavailableGenerator())

        var edited = editor.definition
        edited.source = "function preview(input, options, api) { return (options.prefix === 'true' ? 'id:' : '') + api.seed; }"
        edited.regenerateTitle = "Generate Again"
        edited.options = [.init(id: "prefix", label: "Prefix", defaultValue: "false")]
        editor.scriptText = try ToolScriptDocument.text(for: edited)
        editor.runSample()
        await editor.waitForIdle()
        let first = try #require(editor.trialResult?.output?.primaryText)
        #expect(!first.isEmpty && first != "null")
        #expect(editor.canSave)
        editor.sampleOptions["prefix"] = "true"
        #expect(!editor.canSave)
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText.hasPrefix("id:") == true)
    }

    @Test func openingAnExistingToolPreservesUneditedMetadataSpelling() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        var original = ScriptToolDefinition(id: "custom.labels", title: "Labels", source: "function preview() { return 'ok'; }",
                                            actions: [.init(id: "copy", title: "  Copy  ")], capabilities: ["clipboard.write"])
        original.regenerateTitle = " Again "
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let editor = CustomToolEditorModel(library: library, editing: original.id)
        #expect(!editor.isDirty)
    }

    @Test func generateAndRevertHaveNamedUndoAndRedo() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let generated = ScriptToolDefinition(id: "custom.ignored", title: "Identity", source: "function preview(input) { return input; }")
        let editor = CustomToolEditorModel(library: library, generator: FixedGenerator(definition: generated))
        let original = editor.definition
        #expect(!editor.isRevisingTool)
        editor.description = "Generate an identity tool"
        #expect(!editor.isRevisingTool)
        editor.generate()
        await editor.waitForIdle()
        let undo = editor.undoManager
        #expect(undo.undoActionName == "Generate Tool")
        #expect(editor.isRevisingTool)
        undo.undo()
        #expect(!editor.isRevisingTool)
        #expect(editor.definition == original)
        #expect(editor.description == "Generate an identity tool")
        undo.redo()
        #expect(editor.definition.title == "Identity")
        #expect(editor.description.isEmpty)
        editor.revert()
        #expect(undo.undoActionName == "Revert Changes")
        undo.undo()
        #expect(editor.definition.title == "Identity")
        #expect(editor.isDirty)
        undo.redo()
        #expect(!editor.isDirty)
    }

    @Test func recoveryKeepsIncompleteScriptAndProtectsStaleToolsWithoutSavingPrivateInput() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let original = ScriptToolDefinition(id: "custom.recovery", title: "Original", source: "function preview(input) { return input; }")
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let editor = CustomToolEditorModel(library: library, editing: original.id)

        let valid = editor.scriptText.replacingOccurrences(of: "Original", with: "My draft")
        let incomplete = valid.replacingOccurrences(of: "*/", with: "")
        editor.scriptText = incomplete
        editor.description = "sensitive-prompt"
        editor.sampleInput = "sensitive-sample"
        editor.sampleOptions = ["x": "sensitive-option"]
        editor.flushRecovery()
        let journal = try #require(library.recoveryURL)
        let data = try Data(contentsOf: journal)
        #expect(!String(decoding: data, as: UTF8.self).contains("sensitive-"))
        let recovered = CustomToolEditorModel(library: library)
        #expect(recovered.restoreRecoveryIfAvailable())

        #expect(recovered.scriptText.hasSameUTF8(as: incomplete))
        #expect(recovered.scriptProblem != nil)
        #expect(recovered.description.isEmpty && recovered.sampleOptions.isEmpty)
        #expect(!recovered.canSave && recovered.isDirty)

        var external = original
        external.title = "External"
        try store.save(external, replacing: original)

        recovered.scriptText = valid
        #expect(recovered.definition.title == "My draft")
        recovered.runSample()
        await recovered.waitForIdle()
        #expect(!recovered.save())
        #expect(try store.load() == [external])
        recovered.discardDraft()
        #expect(!FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func malformedGeneratedSourceAndUnavailableModelLeaveEditableDraft() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let bad = ScriptToolDefinition(id: "custom.bad", title: "Bad", source: "function {")
        let editor = CustomToolEditorModel(library: library, generator: FixedGenerator(definition: bad))
        let original = editor.definition
        editor.description = "Make something"
        editor.generate()
        await editor.waitForIdle()
        #expect(editor.isError)
        #expect(editor.definition == original)
        #expect(!editor.canSave)
        let unavailable = CustomToolEditorModel(library: library, generator: UnavailableGenerator())
        unavailable.description = "Make something"
        unavailable.generate()
        #expect(unavailable.isError)
        #expect(unavailable.unavailableReason == "Model unavailable for this test")

        unavailable.scriptText = unavailable.scriptText.replacingOccurrences(of: "input.trim()", with: "'manual'")
        unavailable.runSample()
        await unavailable.waitForIdle()
        #expect(unavailable.trialResult?.output?.primaryText == "manual")
    }

    @Test func actionTrialsReturnRequestedCopyWithoutSavingTheSample() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, generator: UnavailableGenerator())
        var edited = editor.definition
        edited.actions = [.init(id: "copy", title: "Copy Trimmed Text")]
        edited.capabilities = ["clipboard.write"]
        edited.source += "\nfunction perform(action, input, options, api) { api.clipboard.writeText(input.trim()); }"
        editor.scriptText = try ToolScriptDocument.text(for: edited)
        editor.sampleInput = " hello "
        editor.tryAction("copy")
        await editor.waitForIdle()
        #expect(editor.trialWasAction)
        #expect(editor.trialResult?.output?.primaryText == "hello")
        #expect(!editor.canSave)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func buttonTrialsReuseThePreviewSeedAndEvaluationTime() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, generator: UnavailableGenerator())
        var edited = editor.definition
        edited.source = """
        function makeSeed(options, api) { return api.entropy.slice(0, 8).join('-'); }
        function preview(input, options, api) { return api.seed + '@' + api.now; }
        function perform(action, input, options, api) { api.clipboard.writeText(preview(input, options, api)); }
        """
        edited.regenerateTitle = "Generate Again"
        edited.actions = [.init(id: "copy", title: "Copy Generated Value")]
        edited.capabilities = ["clipboard.write"]
        editor.scriptText = try ToolScriptDocument.text(for: edited)
        editor.runSample()
        await editor.waitForIdle()
        let preview = try #require(editor.trialResult?.output?.primaryText)
        editor.tryAction("copy")
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == preview)
    }

    @Test func builtInOpensForRevision() {
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: directory()))
        let editor = CustomToolEditorModel(library: library, editing: "color.rgb")
        #expect(editor.isRevisingTool)
    }

    @Test func typedDescriptionIsProtectedUntilSuccessfulGeneration() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let original = ScriptToolDefinition(id: "custom.original", title: "Original", source: "function preview(input) { return input; }")
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let editor = CustomToolEditorModel(library: library, generator: FixedGenerator(definition: original), editing: original.id)
        #expect(editor.isRevisingTool)
        editor.description = "Keep the same behavior"
        #expect(editor.isDirty)
        editor.selectDocument("new")
        #expect(editor.documentID == original.id)
        #expect(editor.description == "Keep the same behavior")
        editor.generate()
        await editor.waitForIdle()
        #expect(!editor.isError)
        #expect(!editor.isDirty)
        #expect(editor.description.isEmpty)
        editor.selectDocument("new")
        #expect(editor.documentID == "new")
        let newGenerator = RepairGenerator(repaired: original)
        let fresh = CustomToolEditorModel(library: library, generator: newGenerator)
        fresh.description = "Make a new identity transform"
        fresh.generate()
        await fresh.waitForIdle()
        #expect(newGenerator.receivedIsNew == true)
    }

    @Test func generationCanRepairInvalidSourceWhileTrialAndSaveStillValidate() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let original = ScriptToolDefinition(id: "custom.original", title: "Original", source: "function preview(input) { return input; }")
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let generator = RepairGenerator(repaired: original)
        let editor = CustomToolEditorModel(library: library, generator: generator, editing: original.id)

        editor.scriptText = editor.scriptText.replacingOccurrences(of: "return input", with: "retun input")
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.isError)
        #expect(!editor.canSave)
        editor.save()
        #expect(try store.load() == [original])
        editor.description = "Fix the syntax typo in the source"
        editor.generate()
        await editor.waitForIdle()
        #expect(!editor.isError)
        #expect(generator.receivedSource == "function preview(input) { retun input; }")
        #expect(editor.definition.source == original.source)
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.canSave)
    }

    @Test func changingControlDeclarationsKeepsTheSampleInspectorAndRuntimeInSync() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let editor = CustomToolEditorModel(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)))
        let original = """
        /* @toolchord
        { "apiVersion":1, "id":"custom.pick", "title":"Pick",
          "options":[{"id":"letter","label":"Letter","defaultValue":"a",
                      "choices":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}] }
        */
        function preview(input, options) { return options.letter; }
        """
        editor.scriptText = original
        editor.sampleOptions["letter"] = "b"
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "b")
        editor.scriptText = original.replacingOccurrences(of: #""id":"b""#, with: #""id":"a""#)
        #expect(editor.scriptProblem != nil)
        #expect(editor.declaredOptions.isEmpty && !editor.canSave)
        editor.scriptText = original.replacingOccurrences(of: #""id":"b""#, with: #""id":"c""#)
        #expect(editor.scriptProblem == nil && editor.sampleOptions.isEmpty)
        #expect(editor.declaredOptions.first?.defaultValue == "a")
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "a")
    }

    @Test func legacyJournalRecoversIncompleteOptionTextAndUnsavedJavaScript() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let editor = CustomToolEditorModel(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)))
        let journal = try #require(editor.library.recoveryURL)
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let draft = ScriptToolDefinition(id: "custom.old", title: "Unsaved",
                                        source: """
                                        function preview(input) { return input + 'draft'; }
                                        function perform(action, input, options, api) { api.clipboard.writeText(input); }
                                        """)
        var expected = draft
        expected.source = "function preview(input) { return input; }"
        try editor.library.save(expected, replacing: nil)
        let definition = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))
        let installed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expected))
        let legacy: [String: Any] = ["expected": installed, "fields": [
            "definition": definition, "actionLines": "copy | Copy", "allowsClipboardWrite": true,
            "optionsJSON": "[unfinished", "regenerateTitle": "Again"
        ]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: journal)
        try #require(editor.restoreRecoveryIfAvailable())
        #expect(editor.isDirty && editor.scriptProblem != nil)
        #expect(editor.scriptText.contains("[unfinished"))
        #expect(editor.scriptText.contains(draft.source))
        editor.scriptText = editor.scriptText.replacingOccurrences(of: #""[unfinished""#, with: "[]")
        #expect(editor.scriptProblem == nil)
        #expect(editor.definition.id == draft.id && editor.definition.title == draft.title)
        #expect(editor.definition.regenerateTitle == "Again")
        #expect(editor.draftActions == [.init(id: "copy", title: "Copy")])
        #expect(editor.definition.capabilities == ["clipboard.write"])
        editor.runSample()
        await editor.waitForIdle()
        try #require(editor.save())
        #expect(try editor.library.document(for: draft.id).definition.source == draft.source)
    }

    @Test func changingIDIsRejectedOnSave() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder)
        let original = ScriptToolDefinition(id: "custom.keep-id", title: "Keep ID", source: "function preview(input) { return input; }")
        try store.save(original, replacing: nil)
        let library = CustomToolLibrary(store: store)
        library.reload()
        let editor = CustomToolEditorModel(library: library, editing: original.id)

        editor.scriptText = editor.scriptText.replacingOccurrences(of: original.id, with: "custom.new-id")
        editor.runSample()
        await editor.waitForIdle()

        #expect(!editor.save())
        #expect(editor.isError)

        let persisted = try store.load()
        #expect(persisted.count == 1)
        #expect(persisted[0].id == original.id)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOLCHORD_RENDER_CUSTOM_EDITOR"] == "1"))
    func renderEditorForVisualInspection() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = NSApplication.shared
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let script = CustomToolEditorModel(library: library, editing: "json.format")
        script.sampleInput = #"{"name":"Toolchord","counts":[1,2]}"#
        script.runSample()
        await script.waitForIdle()
        try #require(script.trialResult?.isSuccess == true)
        let newTool = CustomToolEditorModel(library: library, generator: UnavailableGenerator())
        for (name, editor, size, appearance) in [
            ("standard", script, NSSize(width: 1020, height: 780), NSAppearance.Name.aqua),
            ("minimum", newTool, NSSize(width: 820, height: 620), NSAppearance.Name.darkAqua),
        ] {
            let host = NSHostingView(rootView: CustomToolEditorView(model: editor))
            host.frame = NSRect(origin: .zero, size: size)
            let background = NSView(frame: host.frame)
            background.wantsLayer = true
            background.layer?.backgroundColor = (appearance == .aqua ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.15, alpha: 1)).cgColor
            background.addSubview(host)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: appearance)
            window.contentView = background
            window.layoutIfNeeded()
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(60))
            }
            let bitmap = try #require(background.bitmapImageRepForCachingDisplay(in: background.bounds))
            background.cacheDisplay(in: background.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("toolchord-custom-editor-\(name).png"))
        }
    }
}

@MainActor
private struct UnavailableGenerator: ScriptGenerating {
    let unavailableReason: String? = "Model unavailable for this test"
    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition { throw ToolDiagnostic("Unavailable") }
}

@MainActor
private struct FixedGenerator: ScriptGenerating {
    let definition: ScriptToolDefinition
    var unavailableReason: String? { nil }
    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition { definition }
}

@MainActor
private final class RepairGenerator: ScriptGenerating {
    let repaired: ScriptToolDefinition
    private(set) var receivedSource: String?
    private(set) var receivedIsNew: Bool?
    var unavailableReason: String? { nil }
    init(repaired: ScriptToolDefinition) { self.repaired = repaired }
    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition {
        receivedSource = current.source
        receivedIsNew = isNew
        return repaired
    }
}
