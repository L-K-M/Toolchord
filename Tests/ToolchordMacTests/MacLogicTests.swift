import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct KeyboardShortcutTests {
    @Test func defaultAvoidsSystemShortcuts() {
        let shortcut = KeyboardShortcut.defaultShortcut
        #expect(shortcut.displayString == "⌥⇧Space")
        #expect(shortcut.problem == nil)
        #expect(shortcut.accessibilityLabel == "Option Shift Space")
    }

    // The macOS shortcuts the recorder checks.
    private static let spotlight = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.command])
    private static let finderSearch = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.command, .option])
    private static let previousInputSource = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.control])
    private static let nextInputSource = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.control, .option])
    private static let appSwitcher = KeyboardShortcut(keyCode: UInt16(kVK_Tab), modifierFlags: [.command])
    private static let reverseAppSwitcher = KeyboardShortcut(keyCode: UInt16(kVK_Tab), modifierFlags: [.command, .shift])
    private static let nextWindow = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Grave), modifierFlags: [.command])
    private static let macOSShortcuts = [
        spotlight, finderSearch, previousInputSource, nextInputSource, appSwitcher, reverseAppSwitcher, nextWindow,
    ]

    @Test func reservedAndIncompleteShortcutsAreRejected() {
        let space = UInt16(kVK_Space)
        #expect(Self.spotlight.validationProblem(character: nil, systemShortcuts: .enabled([Self.spotlight])) == .reserved(
            "⌘Space opens Spotlight. To use it here, turn it off in System Settings → Keyboard → Keyboard Shortcuts → Spotlight."
        ))
        #expect(KeyboardShortcut(keyCode: space, modifierFlags: [.shift]).problem == .needsModifier)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []).problem == .needsModifier)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_F5), modifierFlags: []).problem == nil)
    }

    @Test func paletteCommandShortcutsAreRejected() {
        // Character reservations follow the keyboard layout, so pass the
        // character the palette would see with ⌘ held.
        let command = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command])
        let reserved: [(String, String)] = [
            ("c", "⌘C copies the selection in Toolchord."),
            ("x", "⌘X cuts the selection in Toolchord."),
            ("v", "⌘V pastes or attaches input in Toolchord."),
            ("a", "⌘A selects all in Toolchord."),
            ("z", "⌘Z undoes in Toolchord."),
            ("k", "⌘K opens the Toolchord actions menu."),
            ("r", "⌘R regenerates a value in Toolchord."),
            ("w", "⌘W closes the Toolchord panel."),
            ("f", "⌘F finds text in Toolchord."),
            (",", "⌘, opens Toolchord settings."),
        ]
        for (character, message) in reserved {
            #expect(command.validationProblem(character: character, systemShortcuts: .unknown) == .reserved(message), Comment(rawValue: character))
        }
        let redo = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command, .shift])
        #expect(redo.validationProblem(character: "z", systemShortcuts: .unknown) == .reserved("⇧⌘Z redoes in Toolchord."))
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_Return), modifierFlags: [.command]).problem != nil)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifierFlags: [.command]).problem != nil)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_Return), modifierFlags: [.command, .shift]).problem != nil)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_Delete), modifierFlags: [.command, .shift]).problem != nil)
        #expect(KeyboardShortcut.optionShiftSpace.problem == nil)
        #expect(KeyboardShortcut.controlCommandSpace.problem == nil)
        #expect(KeyboardShortcut.controlOptionCommandSpace.problem == nil)
    }

    @Test func controlCommandSpaceIsAllowedWithANote() {
        let shortcut = KeyboardShortcut.controlCommandSpace
        #expect(shortcut.problem == nil)
        #expect(shortcut.displayString == "⌃⌘Space")
        #expect(shortcut.conflictNote?.contains("Emoji") == true)
    }

    @Test func reservationsFollowTheKeyboardLayout() {
        let physicalA = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command])
        let physicalQ = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: [.command])
        // French AZERTY swaps these letters relative to the ANSI positions.
        #expect(physicalA.validationProblem(character: "q", systemShortcuts: .unknown) == .reserved("⌘Q quits apps."))
        // The same physical key types "a" with ⌘ on AZERTY, which Toolchord
        // uses for select all, so it is reserved for that reason.
        #expect(physicalQ.validationProblem(character: "a", systemShortcuts: .unknown) == .reserved("⌘A selects all in Toolchord."))
        // US QWERTY and uppercase translations have the same reservations.
        #expect(physicalQ.validationProblem(character: "Q", systemShortcuts: .unknown) == .reserved("⌘Q quits apps."))
        #expect(physicalA.validationProblem(character: "a", systemShortcuts: .unknown) == .reserved("⌘A selects all in Toolchord."))
        // Extra modifiers remain available for a custom global shortcut.
        let modifiedQ = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command, .option])
        #expect(modifiedQ.validationProblem(character: "q", systemShortcuts: .unknown) == nil)
    }

    @Test func macOSShortcutsAreReservedOnlyWhileTurnedOn() {
        for shortcut in Self.macOSShortcuts {
            let name = shortcut.displayString
            // On in System Settings, or macOS didn't say: reserved.
            #expect(shortcut.validationProblem(character: nil, systemShortcuts: .enabled([shortcut])) != nil, "\(name)")
            #expect(shortcut.validationProblem(character: nil, systemShortcuts: .unknown) != nil, "\(name)")
            // Turned off: free to record.
            #expect(shortcut.validationProblem(character: nil, systemShortcuts: .enabled([])) == nil, "\(name)")
        }
        // Another macOS shortcut being on doesn't reserve this one.
        #expect(Self.nextInputSource.validationProblem(character: nil, systemShortcuts: .enabled([Self.spotlight])) == nil)
        // ⌘Q isn't a macOS shortcut setting, so it stays reserved.
        let commandQ = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: [.command])
        #expect(commandQ.validationProblem(character: "q", systemShortcuts: .enabled([])) == .reserved("⌘Q quits apps."))
    }

    @Test func reservedMessagesSayWhereToTurnTheShortcutOff() {
        #expect(Self.nextInputSource.validationProblem(character: nil, systemShortcuts: .unknown) == .reserved(
            "⌃⌥Space switches input sources. To use it here, turn it off in System Settings → Keyboard → Keyboard Shortcuts → Input Sources."
        ))
        // The app switcher can't be turned off.
        #expect(Self.appSwitcher.validationProblem(character: nil, systemShortcuts: .unknown) == .reserved("⌘Tab switches apps."))
        // The window switcher is named by its key's label (⌘< on ISO keyboards).
        #expect(Self.nextWindow.validationProblem(character: nil, systemShortcuts: .unknown) == .reserved(
            "\(Self.nextWindow.displayString) switches windows. To use it here, turn it off in System Settings → Keyboard → Keyboard Shortcuts → Keyboard."
        ))
    }

    @Test func readsTurnedOnShortcutsFromHIToolboxEntries() {
        func entry(_ keyCode: Int, _ modifiers: Int, enabled: Bool) -> [String: Any] {
            [kHISymbolicHotKeyCode: keyCode, kHISymbolicHotKeyModifiers: modifiers, kHISymbolicHotKeyEnabled: enabled]
        }
        let system = SystemShortcuts(entries: [
            entry(kVK_Space, controlKey | optionKey, enabled: false),
            entry(kVK_Space, cmdKey, enabled: true),
            // Listed twice, once on: on.
            entry(kVK_ANSI_Grave, cmdKey, enabled: false),
            entry(kVK_ANSI_Grave, cmdKey, enabled: true),
            // fn (0x20000) combinations can't be recorded, so this doesn't reserve ⌃Space.
            entry(kVK_Space, controlKey | 0x20000, enabled: true),
            // Missing modifiers: skipped rather than read as Space alone.
            [kHISymbolicHotKeyCode: kVK_Space, kHISymbolicHotKeyEnabled: true],
        ])
        #expect(!system.mayUse(Self.nextInputSource))
        #expect(system.mayUse(Self.spotlight))
        #expect(system.mayUse(Self.nextWindow))
        #expect(!system.mayUse(Self.previousInputSource))
        #expect(!system.mayUse(KeyboardShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: 0)))
    }

    @Test func modifierOrderFollowsApple() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.command, .shift, .option, .control])
        #expect(shortcut.modifierSymbols == "⌃⌥⇧⌘")
        #expect(KeyboardShortcut(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers).modifierFlags == [.command, .shift, .option, .control])
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(KeyboardShortcut.controlCommandSpace)
        #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == .controlCommandSpace)
    }
}

@MainActor
@Suite struct AppPreferencesTests {
    private func makeDefaults(name: String = "ToolchordTests.\(UUID().uuidString)") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func storesOnlySettingsAndCommandIDs() {
        let suite = "ToolchordTests.\(UUID().uuidString)"
        let defaults = makeDefaults(name: suite)
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.shortcut == .defaultShortcut)
        #expect(!preferences.hasStoredShortcut)
        preferences.shortcut = .controlCommandSpace
        preferences.indent = .four
        preferences.recordUse(of: "json.format")
        preferences.recordUse(of: "uuid.v4")
        preferences.recordUse(of: "json.format")

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.shortcut == .controlCommandSpace)
        #expect(reloaded.indent == .four)
        #expect(reloaded.recentCommandIDs == ["json.format", "uuid.v4"])
        let stored = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        #expect(stored.isSubset(of: ["shortcut", "hasCompletedWelcome", "indent", "recentCommandIDs", "remembersRecentCommands", "showsMenuBarIcon"]), "\(stored)")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func recentsAreBoundedAndCanBeTurnedOff() {
        let preferences = AppPreferences(defaults: makeDefaults())
        for id in ["a", "b", "c", "d", "e"] { preferences.recordUse(of: id) }
        #expect(preferences.recentCommandIDs == ["e", "d", "c", "b"])
        preferences.remembersRecents = false
        #expect(preferences.recentCommandIDs.isEmpty)
        preferences.recordUse(of: "f")
        #expect(preferences.recentCommandIDs.isEmpty)
    }

    @Test func invalidStoredShortcutFallsBackToDefault() throws {
        let suite = "ToolchordTests.\(UUID().uuidString)"
        let defaults = makeDefaults(name: suite)
        // ⌘↵ copies and closes the panel, so it is reserved on every Mac and
        // keyboard layout, unlike the macOS shortcuts, which can be turned off.
        let reserved = KeyboardShortcut(keyCode: UInt16(kVK_Return), modifierFlags: [.command])
        defaults.set(try JSONEncoder().encode(reserved), forKey: "shortcut")
        #expect(AppPreferences(defaults: defaults).shortcut == .defaultShortcut)
        defaults.removePersistentDomain(forName: suite)

        let validSuite = "ToolchordTests.\(UUID().uuidString)"
        let validDefaults = makeDefaults(name: validSuite)
        validDefaults.set(try JSONEncoder().encode(KeyboardShortcut.controlCommandSpace), forKey: "shortcut")
        #expect(AppPreferences(defaults: validDefaults).shortcut == .controlCommandSpace)
        validDefaults.removePersistentDomain(forName: validSuite)
    }

    @Test func corruptStoredShortcutFallsBackToDefault() throws {
        // Values no key press produces: a key code wider than 16 bits, and a
        // modifier bit other than ⌃⌥⇧⌘.
        let corrupt = [
            KeyboardShortcut(keyCode: 70_000, carbonModifiers: UInt32(cmdKey | optionKey)),
            KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey) | 0x1_0000),
        ]
        for stored in corrupt {
            let suite = "ToolchordTests.\(UUID().uuidString)"
            let defaults = makeDefaults(name: suite)
            defaults.set(try JSONEncoder().encode(stored), forKey: "shortcut")
            #expect(AppPreferences(defaults: defaults).shortcut == .defaultShortcut, "\(stored)")
            defaults.removePersistentDomain(forName: suite)
        }
        // Naming a key code that wide doesn't trap.
        #expect(KeyNames.name(for: 70_000) == "Key 70000")
    }

    @Test func indentationPreferenceAppliesToFormatters() throws {
        let preferences = AppPreferences(defaults: makeDefaults())
        preferences.indent = .tab
        let format = try #require(ToolCatalog.command(id: "json.format"))
        let minify = try #require(ToolCatalog.command(id: "json.minify"))
        #expect(preferences.defaultOptions(for: format).values == ["indent": "tab"])
        #expect(preferences.defaultOptions(for: minify).values.isEmpty)
    }
}

@Suite struct ErrorContextTests {
    @Test func showsTheLineWithACaret() throws {
        let context = try #require(ErrorContext(text: "{\n  \"a\": }", location: TextLocation(line: 2, column: 8)))
        #expect(context.line == "  \"a\": }")
        #expect(context.caret == "       ^")
    }

    @Test func handlesCRLFAndMissingLines() throws {
        let context = try #require(ErrorContext(text: "a\r\nbc", location: TextLocation(line: 2, column: 2)))
        #expect(context.line == "bc")
        #expect(context.caret == " ^")
        #expect(ErrorContext(text: "a", location: TextLocation(line: 3, column: 1)) == nil)
    }

    @Test func windowsLongLinesAroundTheColumn() throws {
        let line = String(repeating: "x", count: 500)
        let context = try #require(ErrorContext(text: line, location: TextLocation(line: 1, column: 300), width: 40))
        #expect(context.line.hasPrefix("…") && context.line.hasSuffix("…"))
        let caretIndex = context.caret.count - 1
        #expect(Array(context.line)[caretIndex] == "x")
    }
}

@MainActor
@Suite struct ScreenLocatorTests {
    @Test func frameIsCenteredHorizontallyAndClamped() throws {
        let screen = try #require(NSScreen.screens.first)
        let frame = ScreenLocator.frame(for: CGSize(width: 760, height: 460), on: screen)
        let visible = screen.visibleFrame
        #expect(abs(frame.midX - visible.midX) <= 1)
        #expect(visible.contains(frame))
        let huge = ScreenLocator.frame(for: CGSize(width: 100_000, height: 100_000), on: screen)
        #expect(visible.contains(huge))
    }

    @Test func quartzRectsFlipToCocoa() throws {
        let primary = try #require(NSScreen.screens.first)
        let rect = ScreenLocator.cocoaRect(fromQuartz: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(rect.minX == 10)
        #expect(rect.maxY == primary.frame.height - 20)
    }
}

@MainActor
@Suite struct EditorUndoTests {
    /// Review P1: type, Clear Input, then ⌘Z used to raise NSRangeException.
    @Test func externalReplacementKeepsUndoConsistent() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: true)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        let undoManager = try #require(textView.undoManager)
        undoManager.groupsByEvent = false

        // Typing over two events, then Clear Input in a third, as in the app.
        // Before the fix, the second undo raised NSRangeException.
        undoManager.beginUndoGrouping()
        textView.insertText("sec", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        textView.insertText("ret", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoManager.endUndoGrouping()
        #expect(textView.string == "secret")

        undoManager.beginUndoGrouping()
        CodeTextView.replaceAllText(in: textView, with: "")
        undoManager.endUndoGrouping()
        #expect(textView.string.isEmpty)

        undoManager.undo()
        #expect(textView.string == "secret")
        while undoManager.canUndo { undoManager.undo() }
        #expect(textView.string.isEmpty)
        undoManager.redo()
        #expect(!textView.string.isEmpty)
    }

    @Test func replacementInTheSameEventAsTypingIsSafe() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: true)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        let undoManager = try #require(textView.undoManager)
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        textView.insertText("secret", replacementRange: NSRange(location: NSNotFound, length: 0))
        CodeTextView.replaceAllText(in: textView, with: "")
        undoManager.endUndoGrouping()
        undoManager.undo()
        #expect(textView.string.isEmpty)
    }
}

@MainActor
@Suite struct PanelShortcutTests {
    private func key(_ keyCode: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = [.command]) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
        ))
    }

    private func key(_ keyCode: Int, characters: String, ignoringModifiers: String, _ flags: NSEvent.ModifierFlags = [.command]) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: ignoringModifiers, isARepeat: false, keyCode: UInt16(keyCode)
        ))
    }

    /// Follow-up review P2: Dvorak – QWERTY ⌘ types Dvorak letters but
    /// switches to QWERTY while ⌘ is held. ANSI Comma types "w" alone and ","
    /// with ⌘, so ⌘, must open Settings rather than close the palette.
    @Test func dvorakQwertyCommandUsesTheCommandMapping() throws {
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Comma, characters: ",", ignoringModifiers: "w")) == .settings)
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_V, characters: "v", ignoringModifiers: "k")) == .edit(#selector(NSText.paste(_:))))
        // QWERTY W types "," without ⌘: ⌘W must still close, not open Settings.
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_W, characters: "w", ignoringModifiers: ",")) == .close)
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Z, characters: "Z", ignoringModifiers: ":", [.command, .shift])) == .edit(Selector(("redo:"))))
        // Without ⌘ the Command mapping doesn't apply.
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Comma, characters: "w", ignoringModifiers: "w", [])) == nil)
    }

    /// The Command-state translation itself, with the built-in Dvorak – QWERTY ⌘
    /// layout loaded directly (the active input source doesn't change).
    @Test func dvorakQwertyCommandTranslation() throws {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.DVORAK-QWERTYCMD"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        let layout = try #require(sources?.first, "Dvorak – QWERTY ⌘ ships with macOS")
        #expect(KeyNames.character(for: UInt32(kVK_ANSI_Comma), commandState: false, in: layout) == "w")
        #expect(KeyNames.character(for: UInt32(kVK_ANSI_Comma), commandState: true, in: layout) == ",")
        #expect(KeyNames.character(for: UInt32(kVK_ANSI_Q), commandState: false, in: layout) == "'")
        #expect(KeyNames.character(for: UInt32(kVK_ANSI_Q), commandState: true, in: layout) == "q")
    }

    /// Review P2: on French AZERTY the key in the ANSI W position types "z".
    @Test func azertyCommandZIsUndoNotClose() throws {
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_W, "z")) == .edit(Selector(("undo:"))))
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Z, "w")) == .close)
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Q, "a")) == .edit(#selector(NSText.selectAll(_:))))
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_W, "Z", [.command, .shift])) == .edit(Selector(("redo:"))))
    }

    @Test func usLayoutAndLayoutIndependentKeys() throws {
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_K, "k")) == .actions)
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_Comma, ",")) == .settings)
        #expect(PalettePanel.shortcut(for: try key(kVK_Return, "\r")) == .copyAndClose)
        #expect(PalettePanel.shortcut(for: try key(kVK_Return, "\r", [.command, .shift])) == .copyWithoutClosing)
        #expect(PalettePanel.shortcut(for: try key(kVK_Delete, "\u{7f}", [.command, .shift])) == .clearInput)
        #expect(PalettePanel.shortcut(for: try key(kVK_ANSI_K, "k", [])) == nil)
        #expect(PalettePanel.shortcut(for: try key(kVK_Return, "\r", [])) == nil)
    }
}

@MainActor
@Suite struct ShortcutRecorderTests {
    /// Review P3: an accessibility press must focus the recorder like a click,
    /// or the recorded keystrokes go to whichever view had focus.
    @Test func accessibilityPressFocusesTheRecorder() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let textView = NSTextView(frame: NSRect(x: 0, y: 60, width: 320, height: 40))
        let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 168, height: 26))
        container.addSubview(textView)
        container.addSubview(recorder)
        window.contentView = container
        window.makeFirstResponder(textView)
        #expect(window.firstResponder === textView)

        #expect(recorder.accessibilityPerformPress())
        #expect(window.firstResponder === recorder)
        #expect(recorder.isRecording)

        // A second press cancels, like a second click.
        #expect(recorder.accessibilityPerformPress())
        #expect(!recorder.isRecording)
    }
}
