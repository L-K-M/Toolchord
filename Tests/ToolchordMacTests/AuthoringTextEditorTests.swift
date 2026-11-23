import AppKit
import SwiftUI
import Testing
@testable import ToolchordMac

@MainActor
@Suite struct AuthoringTextEditorTests {
    @Test func sampleTypingUndoSurvivesInspectorVisibility() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = ToolEditorWindow(library: CustomToolLibrary(store: ScriptToolStore(directoryURL: folder)), didClose: {})
        let window = try #require(controller.window)
        defer { window.close() }

        func layout() async throws {
            for _ in 0..<4 {
                window.layoutIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func sample(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.accessibilityLabel() == "Sample input for the custom tool" { return text }
            return view.subviews.lazy.compactMap { sample(in: $0) }.first
        }

        try await layout()
        let content = try #require(window.contentView)
        let initial = controller.editor.sampleInput
        let undo = controller.editor.undoManager
        undo.groupsByEvent = false
        do {
            let text = try #require(sample(in: content))
            #expect(!text.isAutomaticQuoteSubstitutionEnabled)
            #expect(!text.isAutomaticDashSubstitutionEnabled)
            window.makeFirstResponder(text)
            undo.beginUndoGrouping()
            text.selectAll(nil)
            text.insertText("a new sample", replacementRange: text.selectedRange())
            undo.endUndoGrouping()
        }
        #expect(controller.editor.sampleInput == "a new sample")
        #expect(undo.canUndo)
        controller.toggleInspector()
        try await layout()
        #expect(sample(in: content) == nil)
        undo.undo()
        #expect(controller.editor.sampleInput == initial)
        undo.redo()
        controller.toggleInspector()
        try await layout()
        #expect(sample(in: content)?.string == "a new sample")
    }
}
