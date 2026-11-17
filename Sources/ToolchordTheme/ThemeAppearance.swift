/// Which appearance the palette uses.
///
/// `.system` follows the Mac and draws the standard colors, which adapt to
/// light and dark. A theme with custom colors pins `.light` or `.dark`,
/// because one fixed color can't stay legible in both.
public enum ThemeAppearance: String, Sendable, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The tone this appearance pins, or nil when it follows the Mac.
    public var pinnedTone: ThemeTone? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
