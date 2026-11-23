import AppKit
import SwiftUI
import ToolchordSession

/// The large search field at the top of the palette.
///
/// Typing edits the query. ↑/↓ move the selection while focus stays here,
/// Return opens the selected tool, and Escape goes back or dismisses. Input
/// methods get Return and Escape first while composing. Paste is routed by
/// the panel's field editor so ⌘V attaches the clipboard as input.
struct SearchField: NSViewRepresentable {
    let session: PaletteSession
    let focus: PaletteFocus
    let onOpen: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onOpen: onOpen, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        // The theme preview in Settings must not take keyboard focus.
        field.refusesFirstResponder = context.environment.isPalettePreview
        context.coordinator.apply(context.environment.paletteStyle, to: field)
        field.setAccessibilityLabel("Find a tool or paste input")
        field.setAccessibilitySubrole(.searchField)
        field.delegate = context.coordinator
        field.stringValue = session.query
        focus.searchField = field
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.onEscape = onEscape
        context.coordinator.apply(context.environment.paletteStyle, to: field)
        focus.searchField = field
        if !field.stringValue.hasSameUTF8(as: session.query) {
            field.stringValue = session.query
        }
        // The field's accessibility value is the query being edited. Keep
        // the current match in its help so VoiceOver can read both.
        let selection = session.selectedCommand.map { "Selected: \($0.title)." } ?? "No tools found."
        field.setAccessibilityHelp("\(selection) Use the arrow keys to select a tool. Press Return to open it or Command-V to attach clipboard input.")
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let session: PaletteSession
        var onOpen: () -> Void
        var onEscape: () -> Void

        private var appliedStyle: PaletteStyle?

        init(session: PaletteSession, onOpen: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self.session = session
            self.onOpen = onOpen
            self.onEscape = onEscape
        }

        /// Sets the field's font and colors for `style`, once per change.
        func apply(_ style: PaletteStyle, to field: NSTextField) {
            guard appliedStyle != style else { return }
            appliedStyle = style
            field.font = style.searchFont
            field.textColor = style.nsColor(.text)
            field.placeholderAttributedString = NSAttributedString(
                string: "Find a tool or paste input…",
                attributes: [.font: style.searchFont, .foregroundColor: style.placeholder]
            )
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            session.setQuery(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            let previousSelection = session.selectedID
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                session.moveSelection(by: 1)
            case #selector(NSResponder.moveUp(_:)):
                session.moveSelection(by: -1)
            case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
                session.moveSelection(by: 6)
            case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
                session.moveSelection(by: -6)
            case #selector(NSResponder.moveToBeginningOfDocument(_:)):
                session.selectFirst()
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                session.selectLast()
            case #selector(NSResponder.insertNewline(_:)):
                onOpen()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            default:
                return false
            }
            if session.selectedID != previousSelection, NSWorkspace.shared.isVoiceOverEnabled,
               let title = session.selectedCommand?.title {
                // Focus stays in the field while the arrow keys change rows.
                NSAccessibility.post(element: control, notification: .announcementRequested, userInfo: [
                    .announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ])
            }
            return true
        }
    }
}
