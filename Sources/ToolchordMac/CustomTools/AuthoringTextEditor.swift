import AppKit
import SwiftUI
import ToolchordCore

/// Plain-text authoring surface with native editing commands and a normal key-view loop.
struct AuthoringTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let monospaced: Bool
    @Environment(CustomToolEditorModel.self) private var model
    @Environment(CustomToolWorkspace.self) private var workspace
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { workspace.editor(for: label, model: model, text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        if let existing = context.coordinator.scrollView { return existing }
        let scroll = NSTextView.scrollableTextView()
        context.coordinator.scrollView = scroll
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.delegate = context.coordinator
        editor.textStorage?.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.font = monospaced ? .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        editor.textContainerInset = NSSize(width: 6, height: 7)
        editor.setAccessibilityLabel(label)
        editor.string = text
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        editor.isEditable = isEnabled
        guard !editor.hasMarkedText(), !editor.string.hasSameUTF8(as: text) else { return }
        context.coordinator.isSynchronizing = true
        defer { context.coordinator.isSynchronizing = false }
        // Generation, revert and their inverses are already one model-level undo operation.
        // Keep the text view alive for earlier typing and avoid registering a second edit.
        editor.breakUndoCoalescing()
        editor.string = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var text: Binding<String>
        var scrollView: NSScrollView?
        private let undo: UndoManager
        var isSynchronizing = false

        init(text: Binding<String>, undo: UndoManager) {
            self.text = text
            self.undo = undo
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronizing, let editor = notification.object as? NSTextView,
                  !editor.hasMarkedText() else { return }
            text.wrappedValue = editor.string
        }

        // Offscreen NSTextViews apply their native typing undo to storage without
        // sending textDidChange after editing has ended.
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard !isSynchronizing, editedMask.contains(.editedCharacters),
                  undo.isUndoing || undo.isRedoing else { return }
            text.wrappedValue = textStorage.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(textView)
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(textView)
            default:
                return false
            }
            return true
        }
    }
}
