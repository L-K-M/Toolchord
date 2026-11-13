import AppKit
import Carbon.HIToolbox

/// A global shortcut: a Carbon virtual key code plus Carbon modifier flags.
public struct KeyboardShortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt32(keyCode), carbonModifiers: Self.carbonFlags(from: modifierFlags))
    }

    /// ⌥⇧Space: avoids Spotlight (⌘Space), Finder search (⌥⌘Space), input
    /// source switching (⌃Space, ⌃⌥Space), and Emoji & Symbols (⌃⌘Space).
    public static let optionShiftSpace = KeyboardShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | shiftKey))
    /// ⌃⌘Space: takes over Emoji & Symbols in every app while Toolchord runs.
    public static let controlCommandSpace = KeyboardShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | cmdKey))
    /// Used when the default cannot be registered (for example on macOS
    /// 15.0–15.1, which rejected Option-only hotkeys in sandboxed apps).
    public static let controlOptionCommandSpace = KeyboardShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))

    public static let defaultShortcut = optionShiftSpace

    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    public static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Modifier symbols in Apple's order (⌃⌥⇧⌘) followed by the key, such as "⌥⇧Space".
    public var displayString: String {
        modifierSymbols + KeyNames.name(for: keyCode, commandState: modifierFlags.contains(.command))
    }

    public var modifierSymbols: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    /// Spoken form for VoiceOver, such as "Option Shift Space".
    public var accessibilityLabel: String {
        var words: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { words.append("Control") }
        if carbonModifiers & UInt32(optionKey) != 0 { words.append("Option") }
        if carbonModifiers & UInt32(shiftKey) != 0 { words.append("Shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { words.append("Command") }
        words.append(KeyNames.spokenName(for: keyCode, commandState: modifierFlags.contains(.command)))
        return words.joined(separator: " ")
    }

    // MARK: - Validation

    public enum Problem: Equatable, Sendable {
        /// Needs ⌘, ⌃, or ⌥ (function keys may stand alone).
        case needsModifier
        /// Owned by macOS; registering it would not work or would break a core shortcut.
        case reserved(String)
    }

    /// A conflict worth telling the user about but allowed.
    public var conflictNote: String? {
        if self == Self.controlCommandSpace {
            return "Replaces Emoji & Symbols (⌃⌘Space) in other apps. Use Globe–E for emoji instead."
        }
        if keyCode == UInt32(kVK_Space) && carbonModifiers == UInt32(optionKey) {
            return "Option–Space types a non-breaking space in many keyboard layouts."
        }
        return nil
    }

    /// Main actor only: the macOS shortcut and keyboard layout lookups aren't
    /// thread safe.
    @MainActor
    public var problem: Problem? {
        validationProblem(
            character: KeyNames.asciiCapableCharacter(for: keyCode, commandState: modifierFlags.contains(.command)),
            systemShortcuts: .current()
        )
    }

    /// Letter reservations follow the layout used for the shortcut's label,
    /// while Space and Tab retain their layout-independent key codes. A macOS
    /// shortcut is reserved only while it's on in `systemShortcuts`.
    func validationProblem(character: String?, systemShortcuts: SystemShortcuts) -> Problem? {
        let flags = modifierFlags
        let isFunctionKey = KeyNames.isFunctionKey(keyCode)
        if !isFunctionKey && flags.intersection([.command, .control, .option]).isEmpty {
            return .needsModifier
        }
        if flags == [.command], character?.lowercased() == "q" {
            return .reserved("⌘Q quits apps.")
        }
        let space = UInt32(kVK_Space)
        let reason: String
        switch (keyCode, flags) {
        case (space, [.command]): reason = "⌘Space opens Spotlight. " + Self.turnOffHint("Spotlight")
        case (space, [.command, .option]): reason = "⌥⌘Space opens a Finder search window. " + Self.turnOffHint("Spotlight")
        case (space, [.control]): reason = "⌃Space switches input sources. " + Self.turnOffHint("Input Sources")
        case (space, [.control, .option]): reason = "⌃⌥Space switches input sources. " + Self.turnOffHint("Input Sources")
        // The app switcher has no setting to turn it off.
        case (UInt32(kVK_Tab), [.command]), (UInt32(kVK_Tab), [.command, .shift]): reason = "⌘Tab switches apps."
        // The key's label: ⌘< on ISO keyboards such as Swiss German.
        case (UInt32(kVK_ANSI_Grave), [.command]): reason = "\(displayString) switches windows. " + Self.turnOffHint("Keyboard")
        default: return nil
        }
        return systemShortcuts.mayUse(self) ? .reserved(reason) : nil
    }

    /// Where to turn off a macOS shortcut, by its Keyboard Shortcuts section.
    private static func turnOffHint(_ section: String) -> String {
        "To use it here, turn it off in System Settings → Keyboard → Keyboard Shortcuts → \(section)."
    }
}

/// Human-readable key names for Carbon virtual key codes.
enum KeyNames {
    /// `commandState` names the key as the layout types it with ⌘ held,
    /// which differs on layouts such as Dvorak – QWERTY ⌘.
    static func name(for keyCode: UInt32, commandState: Bool = false) -> String {
        if let special = specialNames[Int(keyCode)] { return special.symbol }
        if let character = asciiCapableCharacter(for: keyCode, commandState: commandState) { return character.uppercased() }
        return "Key \(keyCode)"
    }

    static func spokenName(for keyCode: UInt32, commandState: Bool = false) -> String {
        if let special = specialNames[Int(keyCode)] { return special.spoken }
        return name(for: keyCode, commandState: commandState)
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(Int(keyCode))
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialNames: [Int: (symbol: String, spoken: String)] = [
        kVK_Space: ("Space", "Space"),
        kVK_Return: ("↩", "Return"),
        kVK_Tab: ("⇥", "Tab"),
        kVK_Delete: ("⌫", "Delete"),
        kVK_ForwardDelete: ("⌦", "Forward Delete"),
        kVK_Escape: ("⎋", "Escape"),
        kVK_LeftArrow: ("←", "Left Arrow"),
        kVK_RightArrow: ("→", "Right Arrow"),
        kVK_UpArrow: ("↑", "Up Arrow"),
        kVK_DownArrow: ("↓", "Down Arrow"),
        kVK_Home: ("↖", "Home"),
        kVK_End: ("↘", "End"),
        kVK_PageUp: ("⇞", "Page Up"),
        kVK_PageDown: ("⇟", "Page Down"),
        kVK_F1: ("F1", "F1"), kVK_F2: ("F2", "F2"), kVK_F3: ("F3", "F3"), kVK_F4: ("F4", "F4"),
        kVK_F5: ("F5", "F5"), kVK_F6: ("F6", "F6"), kVK_F7: ("F7", "F7"), kVK_F8: ("F8", "F8"),
        kVK_F9: ("F9", "F9"), kVK_F10: ("F10", "F10"), kVK_F11: ("F11", "F11"), kVK_F12: ("F12", "F12"),
        kVK_F13: ("F13", "F13"), kVK_F14: ("F14", "F14"), kVK_F15: ("F15", "F15"), kVK_F16: ("F16", "F16"),
        kVK_F17: ("F17", "F17"), kVK_F18: ("F18", "F18"), kVK_F19: ("F19", "F19"), kVK_F20: ("F20", "F20"),
    ]

    /// The character the key produces in the current ASCII-capable layout,
    /// with ⌘ held when `commandState` is set (the mapping menus use for
    /// ⌘ key equivalents).
    static func asciiCapableCharacter(for keyCode: UInt32, commandState: Bool = false) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return character(for: keyCode, commandState: commandState, in: source)
    }

    /// The character `keyCode` produces in the keyboard layout `source`.
    static func character(for keyCode: UInt32, commandState: Bool, in source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                commandState ? UInt32((cmdKey >> 8) & 0xFF) : 0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }
}
