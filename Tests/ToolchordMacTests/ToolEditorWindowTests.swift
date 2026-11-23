import AppKit
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct ToolEditorWindowTests {
    private final class WindowWithSheet: NSWindow {
        var simulatedSheet: NSWindow?
        override var attachedSheet: NSWindow? { simulatedSheet }
    }

    @Test func openRunSaveAndExportAHandwrittenJavaScriptTool() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScriptToolStore(directoryURL: folder.appendingPathComponent("Library"))
        let library = CustomToolLibrary(store: store)
        let controller = ToolEditorWindow(library: library, didClose: {})
        let tool = folder.appendingPathComponent("greet.js")
        let source = """
        /* @toolchord
        {
          "apiVersion": 1, "id": "custom.greet", "title": "Greet", "summary": "",
          "options": [{"id":"upper","label":"Shout","defaultValue":"false"}],
          "actions": [], "capabilities": [], "author": "Example"
        }
        */
        function preview(input, options) {
          return options.upper === "true" ? input.toUpperCase() : input;
        }
        """
        try Data(source.utf8).write(to: tool)
        controller.open(tool)
        let editor = controller.editor
        #expect(editor.scriptText == source)
        #expect(editor.declaredOptions.first?.label == "Shout")
        let updated = source.replacingOccurrences(of: #""defaultValue":"false""#, with: #""defaultValue":"true""#)
        editor.scriptText = updated
        editor.sampleInput = "Hello"
        controller.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "HELLO")
        try #require(editor.save())
        #expect(try Data(contentsOf: store.directoryURL.appendingPathComponent("custom.greet.js")) == Data(updated.utf8))
        let exported = folder.appendingPathComponent("export.js")
        try editor.exportTool(to: exported)
        #expect(try Data(contentsOf: exported) == Data(updated.utf8))
        #expect(try Data(contentsOf: tool) == Data(source.utf8))
    }

    @Test func finderOpenWaitsForTheExportSheet() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: root.appendingPathComponent("Library")))
        let controller = ToolEditorWindow(library: library, didClose: {})
        let window = WindowWithSheet()
        controller.window = window
        let sheet = NSWindow()
        window.simulatedSheet = sheet

        let draft = controller.editor.definition
        var incoming = draft
        incoming.id = "custom.incoming"
        incoming.title = "Incoming tool"
        try library.save(incoming, replacing: nil)
        let url = root.appendingPathComponent("Incoming.toolchord")
        try PortableToolFile.export(incoming, preserving: nil, to: url)
        var later = draft
        later.id = "custom.later"
        try library.save(later, replacing: nil)
        let laterURL = root.appendingPathComponent("Later.toolchord")
        try PortableToolFile.export(later, preserving: nil, to: laterURL)

        var draftsBeforeEachImport: [String] = []
        library.onChange = { [weak controller] _ in
            if let controller { draftsBeforeEachImport.append(controller.editor.definition.id) }
        }
        controller.open(url)
        controller.open(url)
        controller.open(laterURL)
        #expect(controller.editor.definition.id == draft.id)
        controller.select(incoming.id)
        #expect(controller.editor.definition.id == draft.id)

        let destination = root.appendingPathComponent("Exported.toolchord")
        try controller.editor.exportTool(to: destination)
        #expect(try PortableToolFile(reading: destination).definition.id == draft.id)

        window.simulatedSheet = nil
        // The real delegate notification follows dismissal. Posting through
        // NotificationCenter works even with this offscreen test window.
        window.delegate = controller
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        for _ in 0..<100 where controller.editor.definition.id != later.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(draftsBeforeEachImport == [draft.id, incoming.id])
        #expect(controller.editor.definition.id == later.id)
    }
}
