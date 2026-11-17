/// The built-in looks, in gallery order: Default, then light, then dark.
/// Each preset is a separate typed constant, because one large nested
/// literal is slow for the compiler. `ThemeAudit` checks every one in the
/// unit tests, in normal and increased contrast.
public enum ThemePresets {
    public static let standard = ThemePreset(id: "default", name: "Default", tagline: "The native Mac look", theme: .standard)

    public static let all: [ThemePreset] = [
        standard,
        memphis, paper, newsprint, bubblegum, lemonade, peppermint, matcha, vaporwave, frost,
        synthwave, phosphor, amber, midnight, halloween, lagoon, aurora, cosmic, cocoa, smoke, highContrast,
    ]

    /// Monospaced families every Mac ships with: the only ones a preset may
    /// name, so a preset looks the same everywhere.
    public static let shippedCodeFonts: Set<String> = ["Andale Mono", "Courier New", "Menlo", "Monaco", "PT Mono"]

    public static func preset(id: String) -> ThemePreset? {
        all.first { $0.id == id }
    }

    /// The preset whose look `theme` is, if any: picking a preset and
    /// editing a value back to the preset's counts as that preset again.
    public static func matching(_ theme: PaletteTheme) -> ThemePreset? {
        let look = theme.sanitized
        return all.first { $0.theme == look }
    }

    private static func theme(
        _ appearance: ThemeAppearance,
        opacity: Double,
        corners: Double,
        font: String? = nil,
        _ colors: [ThemeColorRole: UInt32]
    ) -> PaletteTheme {
        PaletteTheme(
            appearance: appearance,
            colors: colors.mapValues { ThemeColor($0) },
            surfaceOpacity: opacity,
            cornerRadius: corners,
            codeFontFamily: font
        )
    }

    // MARK: Light

    /// The family's Memphis Group print (Invoque, Zap, Jetty, Nevermore).
    public static let memphis = ThemePreset(id: "memphis", name: "Memphis", tagline: "Loud geometry on cream paper", theme: theme(.light, opacity: 1, corners: 10, [
        .surface: 0xFEFBEC, .well: 0xF5EDD3, .text: 0x000517, .secondaryText: 0x3D3752, .accent: 0xE0009F,
        .code: 0x000517, .keys: 0x00507D, .strings: 0x9E0068, .numbers: 0x843400, .literals: 0x5A22A8,
        .punctuation: 0x5E5873, .comments: 0x5C566E, .success: 0x005A45, .warning: 0x7A4500, .failure: 0xA30032,
    ]))

    public static let paper = ThemePreset(id: "paper", name: "Paper", tagline: "Warm ink on good paper", theme: theme(.light, opacity: 1, corners: 12, font: "PT Mono", [
        .surface: 0xFAF6EE, .well: 0xF0E8D8, .text: 0x2A241B, .secondaryText: 0x5F5446, .accent: 0x8C5728,
        .code: 0x2A241B, .keys: 0x7A3B12, .strings: 0x3D6129, .numbers: 0x8A4600, .literals: 0x6B3E8C,
        .punctuation: 0x857965, .comments: 0x6E6352, .success: 0x2F632F, .warning: 0x7F4D00, .failure: 0xA3302A,
    ]))

    public static let newsprint = ThemePreset(id: "newsprint", name: "Newsprint", tagline: "Black, white, and a red pencil", theme: theme(.light, opacity: 1, corners: 3, font: "Courier New", [
        .surface: 0xF7F7F2, .well: 0xEAEAE3, .text: 0x111111, .secondaryText: 0x4F4F4F, .accent: 0xB81C1C,
        .code: 0x111111, .keys: 0x8B1A1A, .strings: 0x333333, .numbers: 0x5C4300, .literals: 0x6E1E1E,
        .punctuation: 0x6E6E6E, .comments: 0x5A5A5A, .success: 0x1E5E2E, .warning: 0x6E4A00, .failure: 0xB01B1B,
    ]))

    public static let bubblegum = ThemePreset(id: "bubblegum", name: "Bubblegum", tagline: "Pink, purple, and very round", theme: theme(.light, opacity: 1, corners: 26, [
        .surface: 0xFFF0F7, .well: 0xFFE0EE, .text: 0x3D1A3D, .secondaryText: 0x6E4270, .accent: 0xE0368C,
        .code: 0x3D1A3D, .keys: 0x7E25A6, .strings: 0xA82A63, .numbers: 0x0E6E6E, .literals: 0x5B35C7,
        .punctuation: 0x95688A, .comments: 0x7A4D72, .success: 0x17694A, .warning: 0x8A4F00, .failure: 0xB8154F,
    ]))

    public static let lemonade = ThemePreset(id: "lemonade", name: "Lemonade", tagline: "Citrus slices and summer sun", theme: theme(.light, opacity: 1, corners: 22, [
        .surface: 0xFFFBE0, .well: 0xFFF2B3, .text: 0x332D00, .secondaryText: 0x5E5410, .accent: 0xC26A00,
        .code: 0x332D00, .keys: 0x8F4800, .strings: 0x3F6600, .numbers: 0xA3323F, .literals: 0x255F7D,
        .punctuation: 0x857330, .comments: 0x6A5E2C, .success: 0x336613, .warning: 0x8F4700, .failure: 0xA6231B,
    ]))

    public static let peppermint = ThemePreset(id: "peppermint", name: "Peppermint", tagline: "Candy stripes and fresh mint", theme: theme(.light, opacity: 1, corners: 18, [
        .surface: 0xFDFDFD, .well: 0xEEF6F3, .text: 0x1B2B26, .secondaryText: 0x4A5F59, .accent: 0xD7263D,
        .code: 0x1B2B26, .keys: 0xB81D36, .strings: 0x1A6B43, .numbers: 0x94401F, .literals: 0x285F7E,
        .punctuation: 0x6B857D, .comments: 0x56706A, .success: 0x1A6B43, .warning: 0x8A5200, .failure: 0xB81D36,
    ]))

    public static let matcha = ThemePreset(id: "matcha", name: "Matcha", tagline: "Green tea calm", theme: theme(.light, opacity: 1, corners: 16, font: "Menlo", [
        .surface: 0xF3F6EC, .well: 0xE5EDD8, .text: 0x23301C, .secondaryText: 0x4F5E44, .accent: 0x4C7A2E,
        .code: 0x23301C, .keys: 0x3A611E, .strings: 0x6E511A, .numbers: 0x28605F, .literals: 0x62437F,
        .punctuation: 0x6E7D62, .comments: 0x56654B, .success: 0x3A611E, .warning: 0x7D5200, .failure: 0x9C3526,
    ]))

    public static let vaporwave = ThemePreset(id: "vaporwave", name: "Vaporwave", tagline: "Pastel dreams and endless grids", theme: theme(.light, opacity: 1, corners: 22, [
        .surface: 0xFBEFFF, .well: 0xF1DDFA, .text: 0x2D1650, .secondaryText: 0x5F4380, .accent: 0xD12FA6,
        .code: 0x2D1650, .keys: 0x0A627B, .strings: 0x961D72, .numbers: 0x5433B5, .literals: 0x0B6E60,
        .punctuation: 0x8A6EA8, .comments: 0x6E5389, .success: 0x126B4F, .warning: 0x8A4700, .failure: 0xAD1E54,
    ]))

    /// Translucent: the system glass shows through a white wash, and text
    /// stays on the system's own label colors.
    public static let frost = ThemePreset(id: "frost", name: "Frost", tagline: "Icy glass with a cool blue edge", theme: theme(.light, opacity: 0.55, corners: 20, [
        .surface: 0xFFFFFF, .well: 0xEAF2FA, .accent: 0x2F7FD8,
        .keys: 0x1F5FA8, .strings: 0x1A6E60, .numbers: 0x7A43C2, .literals: 0xA33572,
    ]))

    // MARK: Dark

    public static let synthwave = ThemePreset(id: "synthwave", name: "Synthwave", tagline: "Outrun sunset on a neon grid", theme: theme(.dark, opacity: 1, corners: 14, [
        .surface: 0x1A1033, .well: 0x251747, .text: 0xF5F0FF, .secondaryText: 0xC6B5E8, .accent: 0xFF2E97,
        .code: 0xF5F0FF, .keys: 0x36F9F6, .strings: 0xFF8BD1, .numbers: 0xFF9E64, .literals: 0xC792EA,
        .punctuation: 0x9D8CC7, .comments: 0x9F8FCC, .success: 0x72F1B8, .warning: 0xFEDE5D, .failure: 0xFF6B7A,
    ]))

    public static let phosphor = ThemePreset(id: "phosphor", name: "Phosphor", tagline: "Green glow of an old terminal", theme: theme(.dark, opacity: 1, corners: 4, font: "Andale Mono", [
        .surface: 0x050F07, .well: 0x0B1C10, .text: 0xB6FFC4, .secondaryText: 0x6FCC85, .accent: 0x33FF66,
        .code: 0x9CFFB0, .keys: 0x66FF8C, .strings: 0xCCFFD6, .numbers: 0x3DE069, .literals: 0x7DFFA0,
        .punctuation: 0x4BB86A, .comments: 0x52AD69, .success: 0x66FF8C, .warning: 0xE8FF66, .failure: 0xFF6B6B,
    ]))

    public static let amber = ThemePreset(id: "amber", name: "Amber", tagline: "Warm monochrome, gently humming", theme: theme(.dark, opacity: 1, corners: 4, font: "Monaco", [
        .surface: 0x120C02, .well: 0x1E1405, .text: 0xFFC870, .secondaryText: 0xD19A3E, .accent: 0xFFB000,
        .code: 0xFFC870, .keys: 0xFFB000, .strings: 0xFFE0A8, .numbers: 0xFF9A2E, .literals: 0xFFD27A,
        .punctuation: 0xB8862E, .comments: 0xB08636, .success: 0xE8D06A, .warning: 0xFFDD55, .failure: 0xFF7A50,
    ]))

    public static let midnight = ThemePreset(id: "midnight", name: "Midnight", tagline: "Deep blue for late shifts", theme: theme(.dark, opacity: 1, corners: 18, [
        .surface: 0x0E1626, .well: 0x152038, .text: 0xE6EDF7, .secondaryText: 0x9FB0C8, .accent: 0x66AEFF,
        .code: 0xE6EDF7, .keys: 0x82AAFF, .strings: 0xA5E3A0, .numbers: 0xF7C07A, .literals: 0xD6A8FF,
        .punctuation: 0x8796B0, .comments: 0x8796B0, .success: 0x6FD68C, .warning: 0xF5C46B, .failure: 0xFF8A8A,
    ]))

    public static let halloween = ThemePreset(id: "halloween", name: "Halloween", tagline: "Cute-spooky pumpkin night", theme: theme(.dark, opacity: 1, corners: 16, [
        .surface: 0x1E0B33, .well: 0x2A1145, .text: 0xFFF4E6, .secondaryText: 0xDCCBEA, .accent: 0xFF7A1A,
        .code: 0xFFF4E6, .keys: 0xFFB066, .strings: 0xC4F77A, .numbers: 0xD7B8FF, .literals: 0xFFE07A,
        .punctuation: 0xA98BC4, .comments: 0xA890C2, .success: 0xC4F77A, .warning: 0xFFE07A, .failure: 0xFF9DB2,
    ]))

    public static let lagoon = ThemePreset(id: "lagoon", name: "Lagoon", tagline: "Turquoise water over coral", theme: theme(.dark, opacity: 1, corners: 20, [
        .surface: 0x062A33, .well: 0x0B3640, .text: 0xE8FBFA, .secondaryText: 0x9FD3D0, .accent: 0x2EE6C9,
        .code: 0xE8FBFA, .keys: 0x5EE7DF, .strings: 0xFFB4A2, .numbers: 0xFFD27F, .literals: 0x9AD0FF,
        .punctuation: 0x6FB3B0, .comments: 0x7DB5B2, .success: 0x7BE8A8, .warning: 0xFFD27F, .failure: 0xFF8C82,
    ]))

    public static let aurora = ThemePreset(id: "aurora", name: "Aurora", tagline: "Northern lights over snowy peaks", theme: theme(.dark, opacity: 1, corners: 18, [
        .surface: 0x0B1424, .well: 0x111D33, .text: 0xEAF6FF, .secondaryText: 0xA8BFD6, .accent: 0x5CFFB0,
        .code: 0xEAF6FF, .keys: 0x7DF9C2, .strings: 0xB69CFF, .numbers: 0x7FDBFF, .literals: 0xFF9CE0,
        .punctuation: 0x7F95B3, .comments: 0x8299B8, .success: 0x7DF9C2, .warning: 0xFFE58A, .failure: 0xFF8FA3,
    ]))

    public static let cosmic = ThemePreset(id: "cosmic", name: "Cosmic", tagline: "Planets, rockets, and stardust", theme: theme(.dark, opacity: 1, corners: 24, [
        .surface: 0x120E2E, .well: 0x1B1640, .text: 0xF2EEFF, .secondaryText: 0xB7AEE0, .accent: 0xFFC93C,
        .code: 0xF2EEFF, .keys: 0x8FD3FF, .strings: 0xFFA3D7, .numbers: 0xFFC93C, .literals: 0xA5F28B,
        .punctuation: 0x8D85BD, .comments: 0x938BC4, .success: 0xA5F28B, .warning: 0xFFC93C, .failure: 0xFF8A80,
    ]))

    public static let cocoa = ThemePreset(id: "cocoa", name: "Cocoa", tagline: "Marshmallows and quiet midnights", theme: theme(.dark, opacity: 1, corners: 18, font: "Menlo", [
        .surface: 0x2A1C16, .well: 0x36251D, .text: 0xFBEFE6, .secondaryText: 0xD3BBA8, .accent: 0xF2A65A,
        .code: 0xFBEFE6, .keys: 0xF2C094, .strings: 0xB8E0A0, .numbers: 0xF7A8A0, .literals: 0xD9B8F5,
        .punctuation: 0xA88F7C, .comments: 0xB29A87, .success: 0xB8E0A0, .warning: 0xF7D08A, .failure: 0xFF9B8A,
    ]))

    /// Translucent: dark smoke over the system glass, with the system's
    /// own label colors for text.
    public static let smoke = ThemePreset(id: "smoke", name: "Smoke", tagline: "Dark glass, soft and smoky", theme: theme(.dark, opacity: 0.45, corners: 18, [
        .surface: 0x000000, .accent: 0xB794F6,
        .keys: 0x9CC3FF, .strings: 0x9FE0B5, .numbers: 0xF5B888, .literals: 0xE0B0FF,
    ]))

    public static let highContrast = ThemePreset(id: "highContrast", name: "High Contrast", tagline: "Maximum separation, yellow focus", theme: theme(.dark, opacity: 1, corners: 12, font: "Menlo", [
        .surface: 0x000000, .well: 0x141414, .text: 0xFFFFFF, .secondaryText: 0xE0E0E0, .accent: 0xFFD500,
        .code: 0xFFFFFF, .keys: 0x6CF0FF, .strings: 0xFFE066, .numbers: 0xFF9E5E, .literals: 0xFF8AF0,
        .punctuation: 0xCFCFCF, .comments: 0xC4C4C4, .success: 0x5CFF8A, .warning: 0xFFE066, .failure: 0xFF7070,
    ]))
}
