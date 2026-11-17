extension PaletteTheme {
    /// The color an editor starts from when `role` leaves Automatic: the
    /// theme's own, Toolchord's default, or an opaque stand-in for the
    /// system color the role draws now. Code text, punctuation, and comments
    /// follow the theme's text colors, as they do when automatic.
    public func startingColor(for role: ThemeColorRole, tone: ThemeTone) -> ThemeColor {
        if let custom = self[role] { return custom }
        if let own = ThemeDefaults.color(role, tone: tone) { return own }
        switch role {
        case .accent:
            return ThemeReference.systemAccent(tone)
        case .surface:
            return ThemeReference.windowBackground(tone)
        case .well:
            let wash = ThemeReference.wellWash(tone)
            return wash.color.blended(over: startingColor(for: .surface, tone: tone), opacity: wash.opacity).rounded
        case .text, .code:
            return self[.text] ?? ThemeReference.label(tone)
        case .secondaryText, .punctuation, .comments:
            return self[.secondaryText] ?? ThemeReference.secondaryLabel(tone)
        case .keys, .strings, .numbers, .literals, .success, .warning, .failure:
            // `ThemeDefaults` covers these; this keeps the switch exhaustive.
            return ThemeReference.label(tone)
        }
    }
}
