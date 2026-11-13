import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ToolchordMac

/// ⌘V reaches the controller only when no editable text has focus, such as
/// on a read-only result, so the Find field and the editors keep their own
/// Paste.
@MainActor
@Suite struct PanelPasteTests {
    /// A text view that records Paste instead of reading the clipboard.
    final class RecordingTextView: NSTextView {
        private(set) var pastes = 0
        override func paste(_ sender: Any?) { pastes += 1 }
    }

    /// A controller that records each Paste it is asked to handle.
    final class RecordingHandler: PaletteCommandHandling {
        private(set) var pasteRequests = 0
        func copyAndClose() {}
        func copyWithoutClosing() {}
        func showActions() {}
        func openSettings() {}
        func regenerate() {}
        func clearInput() {}
        func escape() {}
        func dismissPanel() {}
        func pasteIntoSearch() {}
        func pasteFromClipboard() { pasteRequests += 1 }
    }

    /// The panel with `view` as its first responder. The panel isn't made
    /// key, so tests don't take keyboard focus from the app in front.
    func panel(focusing view: NSView, handler: RecordingHandler) -> PalettePanel {
        let panel = PalettePanel()
        panel.commandHandler = handler
        panel.contentView?.addSubview(view)
        panel.makeFirstResponder(view)
        return panel
    }

    func commandV(in panel: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: UInt16(kVK_ANSI_V)
        ))
    }

    @Test func editableTextKeepsItsPaste() throws {
        // The input editor is an editable text view.
        let handler = RecordingHandler()
        let editor = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        let panel = panel(focusing: editor, handler: handler)
        defer { panel.close() }
        #expect(panel.firstResponder === editor)
        _ = panel.performKeyEquivalent(with: try commandV(in: panel))
        #expect(handler.pasteRequests == 0)
    }

    @Test func textFieldsKeepTheirPaste() throws {
        // The search field and the Find field edit through a field editor.
        let handler = RecordingHandler()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let panel = panel(focusing: field, handler: handler)
        defer { panel.close() }
        let fieldEditor = try #require(panel.firstResponder as? NSTextView)
        #expect(fieldEditor.isFieldEditor)
        _ = panel.performKeyEquivalent(with: try commandV(in: panel))
        #expect(handler.pasteRequests == 0)
    }

    @Test func readOnlyTextHandsPasteToTheController() throws {
        // A result is read-only; the controller pastes into the input or
        // search field, or explains that a generator takes no input.
        let handler = RecordingHandler()
        let result = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        result.isEditable = false
        let panel = panel(focusing: result, handler: handler)
        defer { panel.close() }
        #expect(panel.firstResponder === result)
        #expect(panel.performKeyEquivalent(with: try commandV(in: panel)))
        #expect(handler.pasteRequests == 1)
        #expect(result.pastes == 0)
    }
}
