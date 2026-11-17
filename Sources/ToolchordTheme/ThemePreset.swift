/// A named look shipped with Toolchord. Picking one copies its theme into
/// the settings, where every value stays editable. Nothing refers to a
/// preset by ID when drawing, so a preset renamed or dropped in a later
/// version can't leave anyone with a palette that won't draw.
public struct ThemePreset: Sendable, Hashable, Identifiable {
    /// Stable: snapshot names and the gallery's selection use it.
    public let id: String
    public let name: String
    public let tagline: String
    public let theme: PaletteTheme

    public init(id: String, name: String, tagline: String, theme: PaletteTheme) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.theme = theme
    }
}
