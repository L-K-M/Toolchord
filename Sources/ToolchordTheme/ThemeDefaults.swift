/// Toolchord's own colors for the roles a theme leaves automatic and the
/// system has no semantic color for: syntax tokens and statuses. The other
/// automatic roles draw system colors (label, accent, window background),
/// which adapt to Increase Contrast by themselves.
public enum ThemeDefaults {
    /// Toolchord's default for `role` in `tone`, or nil when the system
    /// draws it. These keep at least 4.5:1 on the standard panel and wells
    /// in both tones; `ThemeAudit` checks them in the unit tests.
    public static func color(_ role: ThemeColorRole, tone: ThemeTone) -> ThemeColor? {
        switch (role, tone) {
        case (.keys, .light): ThemeColor(0x2F4FB8)
        case (.keys, .dark): ThemeColor(0xA3B5FF)
        case (.strings, .light): ThemeColor(0x1B6E2E)
        case (.strings, .dark): ThemeColor(0x93DCA2)
        case (.numbers, .light): ThemeColor(0x9A4A0B)
        case (.numbers, .dark): ThemeColor(0xF4B57E)
        case (.literals, .light): ThemeColor(0x7D2AA8)
        case (.literals, .dark): ThemeColor(0xD9A6F7)
        case (.success, .light): ThemeColor(0x177437)
        case (.success, .dark): ThemeColor(0x6FD68C)
        case (.warning, .light): ThemeColor(0x945700)
        case (.warning, .dark): ThemeColor(0xF5C46B)
        case (.failure, .light): ThemeColor(0xB3261E)
        case (.failure, .dark): ThemeColor(0xFF9B91)
        case (.accent, _), (.surface, _), (.well, _), (.text, _), (.secondaryText, _), (.code, _), (.punctuation, _), (.comments, _):
            nil
        }
    }
}
