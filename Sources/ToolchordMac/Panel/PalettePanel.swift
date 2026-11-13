import AppKit
import Carbon.HIToolbox

/// Keyboard commands the panel routes to its controller.
@MainActor
protocol PaletteCommandHandling: AnyObject {
    func copyAndClose()
    func copyWithoutClosing()
    func showActions()
    func openSettings()
    func regenerate()
    func clearInput()
    func escape()
    func dismissPanel()
    /// The search field's field editor received a paste command.
    func pasteIntoSearch()
    /// ⌘V with no editable text focused: paste into the input editor or the
    /// search field, or explain that a generator tool takes no input.
    func pasteFromClipboard()
}

/// A borderless, non-activating floating panel.
///
/// `.nonactivatingPanel` must be part of the style mask at initialization:
/// AppKit tags the window for WindowServer only then. The panel becomes key
/// without activating Toolchord, so the app the user was working in keeps
/// its menu bar and regains keyboard focus as soon as the panel closes.
final class PalettePanel: NSPanel {
    weak var commandHandler: PaletteCommandHandling?
    /// The custom field editor for the search field.
    private lazy var searchFieldEditor: SearchFieldEditor = {
        let editor = SearchFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        setAccessibilityLabel("Toolchord")
        setAccessibilitySubrole(.floatingWindow)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Gives the search field a field editor that routes Paste to the session.
    func fieldEditor(for client: Any?) -> NSText? {
        guard client is SearchTextField else { return nil }
        searchFieldEditor.searchField = client as? SearchTextField
        return searchFieldEditor
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if let editor = fieldEditor(for: object) { return editor }
        return super.fieldEditor(createFlag, for: object)
    }

    override func cancelOperation(_ sender: Any?) {
        commandHandler?.escape()
    }

    /// A keyboard command the panel handles itself.
    enum Shortcut: Equatable {
        case copyAndClose, copyWithoutClosing, actions, settings, regenerate, clearInput, close, find
        /// A standard editing command sent to the first responder.
        case edit(Selector)
    }

    /// Classifies a key-down event. Letters and punctuation are matched by the
    /// character the active keyboard layout produces, not the physical key, so
    /// ⌘Z on a French AZERTY keyboard (the key in the ANSI W position) is Undo,
    /// not Close. Return and Delete are matched by key code.
    static func shortcut(for event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = Int(event.keyCode)
        if key == kVK_Return || key == kVK_ANSI_KeypadEnter {
            switch flags {
            case [.command]: return .copyAndClose
            case [.command, .shift]: return .copyWithoutClosing
            default: return nil
            }
        }
        if key == kVK_Delete {
            return flags == [.command, .shift] ? .clearInput : nil
        }
        guard let character = shortcutCharacter(for: event) else { return nil }
        switch (flags, character) {
        case ([.command], "k"): return .actions
        case ([.command], ","): return .settings
        case ([.command], "r"): return .regenerate
        case ([.command], "w"): return .close
        case ([.command], "f"): return .find
        case ([.command], "x"): return .edit(#selector(NSText.cut(_:)))
        case ([.command], "c"): return .edit(#selector(NSText.copy(_:)))
        case ([.command], "v"): return .edit(#selector(NSText.paste(_:)))
        case ([.command], "a"): return .edit(#selector(NSText.selectAll(_:)))
        case ([.command], "z"): return .edit(Selector(("undo:")))
        case ([.command, .shift], "z"): return .edit(Selector(("redo:")))
        default: return nil
        }
    }

    /// The lowercase character for a shortcut, by the rule menus use for key
    /// equivalents: with ⌘ held, what the layout types with ⌘ (layouts such
    /// as Dvorak – QWERTY ⌘ switch to QWERTY then); otherwise what it types
    /// without modifiers; and for non-Latin layouts, the key's character in
    /// the ASCII-capable layout.
    static func shortcutCharacter(for event: NSEvent) -> String? {
        let command = event.modifierFlags.contains(.command)
        for characters in [command ? event.characters : nil, event.charactersIgnoringModifiers] {
            if let lowercase = characters?.lowercased(),
               lowercase.unicodeScalars.count == 1,
               lowercase.unicodeScalars.allSatisfy(\.isASCII) {
                return lowercase
            }
        }
        return KeyNames.asciiCapableCharacter(for: UInt32(event.keyCode), commandState: command)?.lowercased()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        // While an input method is composing, its marked text is not part of
        // the input yet; leave every key to the input method.
        if let textView = firstResponder as? NSTextView, textView.hasMarkedText() {
            return super.performKeyEquivalent(with: event)
        }
        guard let shortcut = Self.shortcut(for: event) else { return super.performKeyEquivalent(with: event) }
        switch shortcut {
        case .copyAndClose: commandHandler?.copyAndClose()
        case .copyWithoutClosing: commandHandler?.copyWithoutClosing()
        case .actions: commandHandler?.showActions()
        case .settings: commandHandler?.openSettings()
        case .regenerate: commandHandler?.regenerate()
        case .clearInput: commandHandler?.clearInput()
        case .close: commandHandler?.dismissPanel()
        case .find:
            if super.performKeyEquivalent(with: event) { return true }
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            return NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: firstResponder, from: item)
        case .edit(let action):
            // Paste with no editable text focused, such as on a read-only
            // result, would do nothing there. The controller pastes into the
            // input editor or search field instead, or explains that a
            // generator tool takes no input. Editable text, such as the input
            // editor, the search field, or a Find field, keeps its own Paste.
            if action == #selector(NSText.paste(_:)), !focusIsOnEditableText, let commandHandler {
                commandHandler.pasteFromClipboard()
                return true
            }
            // Accessory apps may not route standard editing shortcuts through
            // a main menu while another app is active; send them directly.
            if super.performKeyEquivalent(with: event) { return true }
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return true
    }

    /// Whether typed or pasted text would go into the focused view. A search
    /// or Find field edits through a field editor, which is a text view too.
    private var focusIsOnEditableText: Bool {
        (firstResponder as? NSTextView)?.isEditable == true
    }
}

/// The search field. Arrow keys, Return, and Escape are handled by its
/// delegate; Paste is handled by ``SearchFieldEditor``.
final class SearchTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}

/// Field editor for the search field: Paste attaches the clipboard text as
/// input instead of inserting it into the query.
final class SearchFieldEditor: NSTextView {
    weak var searchField: SearchTextField?

    private var handler: PaletteCommandHandling? {
        (window as? PalettePanel)?.commandHandler
    }

    override func paste(_ sender: Any?) {
        handler?.pasteIntoSearch() ?? super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }
}
