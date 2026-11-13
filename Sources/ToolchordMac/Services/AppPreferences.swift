import Foundation
import Observation
import ToolchordCore
import ToolchordSession

/// Settings stored in `UserDefaults`. Never stores payloads, queries, or
/// results: only the shortcut, display preferences, and recently used
/// command IDs.
@MainActor
@Observable
public final class AppPreferences: SessionPreferences {
    public enum Indent: String, CaseIterable, Identifiable, Sendable {
        case two = "2"
        case four = "4"
        case tab = "tab"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .two: "2 spaces"
            case .four: "4 spaces"
            case .tab: "Tab"
            }
        }
    }

    private enum Key {
        static let shortcut = "shortcut"
        static let hasCompletedWelcome = "hasCompletedWelcome"
        static let indent = "indent"
        static let recents = "recentCommandIDs"
        static let remembersRecents = "remembersRecentCommands"
        static let showsMenuBarIcon = "showsMenuBarIcon"
    }

    @ObservationIgnored private let defaults: UserDefaults
    public static let recentLimit = 4

    public var shortcut: KeyboardShortcut {
        didSet { store(shortcut, forKey: Key.shortcut) }
    }

    public var hasCompletedWelcome: Bool {
        didSet { defaults.set(hasCompletedWelcome, forKey: Key.hasCompletedWelcome) }
    }

    public var indent: Indent {
        didSet { defaults.set(indent.rawValue, forKey: Key.indent) }
    }

    public var remembersRecents: Bool {
        didSet {
            defaults.set(remembersRecents, forKey: Key.remembersRecents)
            if !remembersRecents { clearRecents() }
        }
    }

    public var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    public private(set) var recentCommandIDs: [String] {
        didSet { defaults.set(recentCommandIDs, forKey: Key.recents) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.remembersRecents: true,
            Key.showsMenuBarIcon: true,
        ])
        // A stored shortcut may be one the recorder now rejects, such as a
        // palette command key saved by an older build, or corrupt data no key
        // press produces. Fall back rather than register a hotkey that shadows
        // the panel or names no key.
        if let data = defaults.data(forKey: Key.shortcut),
           let stored = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
           stored.isRecordable, stored.problem == nil {
            shortcut = stored
        } else {
            shortcut = .defaultShortcut
        }
        hasCompletedWelcome = defaults.bool(forKey: Key.hasCompletedWelcome)
        indent = Indent(rawValue: defaults.string(forKey: Key.indent) ?? "") ?? .two
        remembersRecents = defaults.bool(forKey: Key.remembersRecents)
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        recentCommandIDs = defaults.stringArray(forKey: Key.recents) ?? []
    }

    /// Whether a shortcut was ever saved (as opposed to the built-in default).
    public var hasStoredShortcut: Bool { defaults.data(forKey: Key.shortcut) != nil }

    public func clearRecents() {
        recentCommandIDs = []
    }

    // MARK: SessionPreferences

    public func defaultOptions(for command: ToolCommand) -> ToolOptions {
        guard command.options.contains(where: { $0.id == "indent" }) else { return ToolOptions() }
        return ToolOptions(["indent": indent.rawValue])
    }

    public func recordUse(of commandID: String) {
        guard remembersRecents else { return }
        var ids = recentCommandIDs.filter { $0 != commandID }
        ids.insert(commandID, at: 0)
        recentCommandIDs = Array(ids.prefix(Self.recentLimit))
    }

    private func store(_ shortcut: KeyboardShortcut, forKey key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }
}
