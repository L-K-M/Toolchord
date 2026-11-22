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
        #expect(library.definitions.isEmpty)
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "hello")
        #expect(editor.canSave)
        editor.definition.title = "Trim My Text"
        #expect(!editor.canSave)
        editor.runSample()
        await editor.waitForIdle()
        editor.save()
        #expect(!editor.isError)
        #expect(!editor.isDirty)
        let persisted = try ScriptToolStore(directoryURL: folder).load()
        #expect(persisted.count == 1)
        #expect(persisted[0].title == "Trim My Text")
        let bytes = try Data(contentsOf: folder.appendingPathComponent("\(persisted[0].id).json"))
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
        editor.definition.summary = "Updated summary"
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
        editor.definition.source = "function preview(input, options, api) { return (options.prefix === 'true' ? 'id:' : '') + api.seed; }"
        editor.regenerateTitle = "Generate Again"
        editor.actionLines = ""
        editor.allowsClipboardWrite = false
        editor.optionsJSON = #"[{"id":"prefix","label":"Prefix","defaultValue":"false"}]"#
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
        unavailable.definition.source = "function preview(input) { return 'manual'; }"
        unavailable.runSample()
        await unavailable.waitForIdle()
        #expect(unavailable.trialResult?.output?.primaryText == "manual")
    }

    @Test func actionTrialsReturnRequestedCopyWithoutSavingTheSample() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let editor = CustomToolEditorModel(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)), generator: UnavailableGenerator())
        editor.actionLines = "copy | Copy Trimmed Text"
        editor.allowsClipboardWrite = true
        editor.definition.source += "\nfunction perform(action, input, options, api) { api.clipboard.writeText(input.trim()); }"
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
        let editor = CustomToolEditorModel(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)), generator: UnavailableGenerator())
        editor.definition.source = """
        function makeSeed(options, api) { return api.entropy.slice(0, 8).join('-'); }
        function preview(input, options, api) { return api.seed + '@' + api.now; }
        function perform(action, input, options, api) { api.clipboard.writeText(preview(input, options, api)); }
        """
        editor.regenerateTitle = "Generate Again"
        editor.actionLines = "copy | Copy Generated Value"
        editor.allowsClipboardWrite = true
        editor.runSample()
        await editor.waitForIdle()
        let preview = try #require(editor.trialResult?.output?.primaryText)
        editor.tryAction("copy")
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == preview)
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
        editor.definition.source = "function preview(input) { retun input; }"
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOLCHORD_RENDER_CUSTOM_EDITOR"] == "1"))
    func renderEditorForVisualInspection() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = NSApplication.shared
        let editor = CustomToolEditorModel(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)), generator: UnavailableGenerator())
        editor.runSample()
        await editor.waitForIdle()
        for (name, size, appearance) in [
            ("standard", NSSize(width: 1020, height: 780), NSAppearance.Name.aqua),
            ("minimum", NSSize(width: 820, height: 620), NSAppearance.Name.darkAqua),
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
