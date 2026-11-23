import AppKit
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct ToolLibrarySidebarTests {
    @Test func filteringByAliasAndPressingReturnOpensTheBuiltInScript() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        #expect(library.reload())
        let controller = ToolEditorWindow(library: library, didClose: {})
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)

        func layout() async throws {
            for _ in 0..<4 {
                window.layoutIfNeeded()
                content.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        try await layout()
        let filter = try #require(descendant(NSTextField.self, in: content) { $0.placeholderString == "Filter tools" })
        func table() throws -> NSTableView {
            try #require(descendant(NSTableView.self, in: content) { _ in true })
        }

        #expect(try table().numberOfRows >= ToolCatalog.commands.count)
        window.makeFirstResponder(filter)
        let fieldEditor = try #require(filter.currentEditor() as? NSTextView)
        fieldEditor.insertText("json validator", replacementRange: fieldEditor.selectedRange())
        try await layout()
        #expect(try table().numberOfRows < ToolCatalog.commands.count)
        #expect(controller.editor.documentID == "new")
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await layout()
        #expect(controller.editor.documentID == "json.validate")
        let script = try #require(descendant(NSTextView.self, in: content) { $0.accessibilityLabel() == "Custom tool JavaScript" })
        #expect(script.isEditable)
        #expect(script.string == controller.editor.definition.source)

        // Opening a different tool from the palette must reveal its row even
        // when a previous library filter excluded it.
        controller.select("xml.validate")
        try await layout()
        #expect(filter.stringValue.isEmpty)
        #expect(try table().numberOfRows >= ToolCatalog.commands.count)
        let revealed = try table()
        #expect(NSLocationInRange(revealed.selectedRow, revealed.rows(in: revealed.visibleRect)))
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView, matching: (T) -> Bool) -> T? {
        if let candidate = view as? T, matching(candidate) { return candidate }
        for child in view.subviews {
            if let result = descendant(type, in: child, matching: matching) { return result }
        }
        return nil
    }
}
