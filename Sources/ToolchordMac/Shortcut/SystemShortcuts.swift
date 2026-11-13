import Carbon.HIToolbox

/// The macOS keyboard shortcuts that are turned on in System Settings →
/// Keyboard → Keyboard Shortcuts, as HIToolbox reports them.
///
/// The recorder reserves a macOS shortcut only while it's on, so someone who
/// turned off Spotlight's ⌘Space or the input source shortcuts can record
/// those keys for Toolchord.
enum SystemShortcuts: Equatable, Sendable {
    /// macOS didn't report its shortcuts, so any of them may be on.
    case unknown
    /// The shortcuts that are on.
    case enabled(Set<KeyboardShortcut>)

    /// Main actor only: `CopySymbolicHotKeys` isn't thread safe.
    @MainActor
    static func current() -> SystemShortcuts {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]]
        else { return .unknown }
        return SystemShortcuts(entries: entries)
    }

    /// Reads `CopySymbolicHotKeys` entries. A combination listed more than
    /// once is on if any of its entries is; entries whose modifiers a
    /// recorded shortcut can't have, such as fn, never match one.
    init(entries: [[String: Any]]) {
        self = .enabled(Set(entries.compactMap { entry -> KeyboardShortcut? in
            guard entry[kHISymbolicHotKeyEnabled] as? Bool == true,
                  let keyCode = (entry[kHISymbolicHotKeyCode] as? Int).flatMap({ UInt32(exactly: $0) }),
                  let modifiers = (entry[kHISymbolicHotKeyModifiers] as? Int).flatMap({ UInt32(exactly: $0) })
            else { return nil }
            return KeyboardShortcut(keyCode: keyCode, carbonModifiers: modifiers)
        }))
    }

    /// Whether macOS may be using `shortcut`: true while it's on, or when
    /// macOS didn't say.
    func mayUse(_ shortcut: KeyboardShortcut) -> Bool {
        switch self {
        case .unknown: return true
        case .enabled(let shortcuts): return shortcuts.contains(shortcut)
        }
    }
}
