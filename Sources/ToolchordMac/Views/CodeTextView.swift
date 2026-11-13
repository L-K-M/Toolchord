import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession

/// Remembers the AppKit views that the controller moves focus between.
@MainActor
final class PaletteFocus {
    weak var searchField: SearchTextField?
    weak var inputEditor: CodeTextView?
    weak var resultView: CodeTextView?

    func focusSearch() {
        guard let searchField, let window = searchField.window else { return }
        if window.firstResponder !== searchField.currentEditor() {
            window.makeFirstResponder(searchField)
        }
        // Put the caret at the end instead of selecting the whole query.
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    func focusEditor() {
        guard let inputEditor, let window = inputEditor.window else { return }
        window.makeFirstResponder(inputEditor)
    }

    func focusResult() {
        guard let resultView, let window = resultView.window else { return }
        window.makeFirstResponder(resultView)
    }
}

/// A plain-text code view. As an input editor it is editable with native
/// undo, find, and IME; as a result view it is read-only but selectable.
/// Escape goes back (after any IME composition), and Tab moves focus;
/// Option-Tab inserts a tab character.
final class CodeTextView: NSTextView {
    /// How Copy writes the selection. A selection of a secret result, such as
    /// a generated random string, is written like the palette's own Copy of
    /// it: kept on this Mac and marked confidential for clipboard history
    /// apps, not as the plain text NSTextView would write.
    var copySensitivity: ClipboardSensitivity = .normal
    /// Receives secret copies; nil means the system clipboard. Tests pass a
    /// private one.
    var secretClipboard: ClipboardWriting?

    override func copy(_ sender: Any?) {
        guard copySensitivity == .secret else {
            super.copy(sender)
            return
        }
        let selection = selectedRanges
            .map { (string as NSString).substring(with: $0.rangeValue) }
            .joined(separator: "\n")
        guard !selection.isEmpty else { return }
        if !(secretClipboard ?? SystemClipboard()).writeText(selection, sensitivity: .secret) {
            NSSound.beep()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            super.cancelOperation(sender)
        } else {
            (window as? PalettePanel)?.commandHandler?.escape()
        }
    }

    override func complete(_ sender: Any?) {
        cancelOperation(sender)
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(self)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(self)
    }

    /// Replaces all text as one undoable change. Assigning `string` directly
    /// would leave earlier typing in the undo stack pointing at ranges that
    /// no longer exist, so a later ⌘Z raises `NSRangeException`.
    static func replaceAllText(in textView: NSTextView, with text: String) {
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.breakUndoCoalescing()
        if textView.allowsUndo, textView.isEditable, textView.shouldChangeText(in: range, replacementString: text) {
            // Its own undo group, so it stays a separate step even if it lands
            // in the same event as typing.
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
            undoManager?.endUndoGrouping()
        } else {
            textView.undoManager?.removeAllActions(withTarget: textView)
            if let storage = textView.textStorage { textView.undoManager?.removeAllActions(withTarget: storage) }
            textView.string = text
        }
    }

    static func makeScrollable(editable: Bool) -> (NSScrollView, CodeTextView) {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = CodeTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = editable
        textView.isEditable = editable
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = Theme.codeFont
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.codeLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Theme.codeFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        scrollView.documentView = textView
        return (scrollView, textView)
    }
}

/// The editable input editor for the expanded tool view.
struct InputEditor: NSViewRepresentable {
    let text: String
    let accessibilityLabel: String
    let focus: PaletteFocus
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: true)
        textView.delegate = context.coordinator
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.lastText = text
        focus.inputEditor = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        focus.inputEditor = textView
        // Only replace the text when it changed outside the editor (for
        // example Clear Input), so typing never loses the caret. Compare bytes,
        // not canonically equivalent strings.
        if !text.hasSameUTF8(as: context.coordinator.lastText) && !text.hasSameUTF8(as: textView.string) {
            context.coordinator.applyExternalText(text, to: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var lastText = ""
        private var isApplyingExternalText = false

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        /// Shows text that changed in the session without echoing it back.
        func applyExternalText(_ text: String, to textView: NSTextView) {
            isApplyingExternalText = true
            defer { isApplyingExternalText = false }
            CodeTextView.replaceAllText(in: textView, with: text)
            lastText = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            lastText = textView.string
            onChange(textView.string)
        }
    }
}

/// A read-only, selectable, syntax-colored result.
struct ResultTextView: NSViewRepresentable {
    let text: String
    let syntax: SyntaxKind
    /// What the result belongs to, such as the command ID. New text with the
    /// same identity comes from an edit, so the reader keeps their place.
    let identity: String
    /// How Copy writes a selection of the result.
    let sensitivity: ClipboardSensitivity
    let dimmed: Bool
    let accessibilityLabel: String
    var focus: PaletteFocus?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: false)
        textView.setAccessibilityLabel(accessibilityLabel)
        apply(to: textView, coordinator: context.coordinator)
        focus?.resultView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        focus?.resultView = textView
        textView.setAccessibilityLabel(accessibilityLabel)
        apply(to: textView, coordinator: context.coordinator)
    }

    private func apply(to textView: CodeTextView, coordinator: Coordinator) {
        coordinator.show(text, syntax: syntax, identity: identity, in: textView)
        textView.copySensitivity = sensitivity
        textView.alphaValue = dimmed ? 0.45 : 1
    }

    @MainActor
    final class Coordinator {
        private var text: String?
        private var syntax: SyntaxKind?
        private var identity: String?

        /// Shows `text` in `textView`. A result for a different identity starts
        /// at the top, even when its text is the same; a changed result for the
        /// same identity, such as after an edit to the input, keeps the scroll
        /// position (AppKit clamps it when the new text is shorter).
        func show(_ text: String, syntax: SyntaxKind, identity: String, in textView: NSTextView) {
            let isNewResult = identity != self.identity
            self.identity = identity
            let isSameText = self.text.map { $0.hasSameUTF8(as: text) } ?? false
            if !isSameText || syntax != self.syntax {
                self.text = text
                self.syntax = syntax
                textView.textStorage?.setAttributedString(SyntaxHighlighter.attributedString(for: text, syntax: syntax))
            }
            if isNewResult { textView.scroll(.zero) }
        }
    }
}
