import AppKit
import SwiftUI
import ToolchordTheme

/// The palette's resolved look: a theme, the text sizes, and the
/// accessibility display settings turned into the colors, fonts, and
/// metrics the views draw with.
///
/// Plain data, so it sits in the SwiftUI environment and compares cheaply:
/// views that cache drawn output, such as the highlighted result, redraw
/// only when it changes. Colors and fonts are made on access. The colors
/// Toolchord draws itself are resolved for both tones up front; under the
/// system appearance they become dynamic colors that follow light and
/// dark, while roles the system draws stay system colors.
struct PaletteStyle: Sendable, Equatable {
    let theme: PaletteTheme
    let textSizes: ThemeTextSizes
    let increaseContrast: Bool
    let reduceTransparency: Bool
    private let lightColors: [ThemeColorRole: ThemeColor]
    private let darkColors: [ThemeColorRole: ThemeColor]

    init(
        theme: PaletteTheme = .standard,
        textSizes: ThemeTextSizes = .standard,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) {
        let theme = theme.sanitized
        self.theme = theme
        self.textSizes = textSizes
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        if let tone = theme.appearance.pinnedTone {
            let drawn = ThemeAudit.drawnColors(for: theme, tone: tone, increasedContrast: increaseContrast)
            lightColors = drawn
            darkColors = drawn
        } else {
            lightColors = ThemeAudit.drawnColors(for: theme, tone: .light, increasedContrast: increaseContrast)
            darkColors = ThemeAudit.drawnColors(for: theme, tone: .dark, increasedContrast: increaseContrast)
        }
    }

    static let standard = PaletteStyle()

    // MARK: Appearance

    /// The appearance the palette pins, in its high-contrast variant under
    /// Increase Contrast as the system's own would be; nil follows the Mac.
    var appearanceName: NSAppearance.Name? {
        switch theme.appearance {
        case .system: nil
        case .light: increaseContrast ? .accessibilityHighContrastAqua : .aqua
        case .dark: increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
        }
    }

    var appearance: NSAppearance? {
        appearanceName.flatMap { NSAppearance(named: $0) }
    }

    // MARK: Colors

    /// The color for `role`. An automatic role draws the system's color;
    /// code text, punctuation, and comments follow the theme's text colors
    /// instead, so a theme that sets only text stays consistent.
    func nsColor(_ role: ThemeColorRole) -> NSColor {
        if let light = lightColors[role], let dark = darkColors[role] {
            return light == dark ? NSColor(theme: light) : .dynamic(light: NSColor(theme: light), dark: NSColor(theme: dark))
        }
        switch role {
        case .accent: return .controlAccentColor
        case .surface: return .windowBackgroundColor
        case .well:
            let light = ThemeReference.wellWash(.light)
            let dark = ThemeReference.wellWash(.dark)
            return .dynamic(
                light: NSColor(theme: light.color).withAlphaComponent(light.opacity),
                dark: NSColor(theme: dark.color).withAlphaComponent(dark.opacity)
            )
        case .text: return .labelColor
        case .secondaryText: return .secondaryLabelColor
        case .code: return nsColor(.text)
        case .punctuation, .comments: return nsColor(.secondaryText)
        // Toolchord always draws these itself (see `ThemeDefaults`).
        case .keys, .strings, .numbers, .literals, .success, .warning, .failure: return .labelColor
        }
    }

    private func isCustom(_ role: ThemeColorRole) -> Bool {
        lightColors[role] != nil && theme[role] != nil
    }

    /// The accent: the person's system accent unless the theme sets one.
    var accent: Color {
        isCustom(.accent) ? Color(nsColor: nsColor(.accent)) : .accentColor
    }

    /// For `.tint`: nil keeps the system accent.
    var tint: Color? {
        isCustom(.accent) ? accent : nil
    }

    /// A custom accent, for drawing the Copy button in it; nil uses the
    /// system's prominent button.
    var customAccent: (fill: Color, label: Color)? {
        guard isCustom(.accent), let accent = lightColors[.accent] else { return nil }
        return (Color(nsColor: NSColor(theme: accent)), Color(nsColor: NSColor(theme: accent.readableForeground)))
    }

    var selection: Color { accent.opacity(ThemeReference.selectionOpacity) }

    var primary: AnyShapeStyle {
        isCustom(.text) ? AnyShapeStyle(Color(nsColor: nsColor(.text))) : AnyShapeStyle(.primary)
    }

    /// The theme's own text color, or nil when text is automatic.
    var customText: Color? {
        isCustom(.text) ? Color(nsColor: nsColor(.text)) : nil
    }

    var secondary: AnyShapeStyle {
        isCustom(.secondaryText) ? AnyShapeStyle(Color(nsColor: nsColor(.secondaryText))) : AnyShapeStyle(.secondary)
    }

    var primaryColor: Color {
        isCustom(.text) ? Color(nsColor: nsColor(.text)) : .primary
    }

    var secondaryColor: Color {
        isCustom(.secondaryText) ? Color(nsColor: nsColor(.secondaryText)) : .secondary
    }

    var success: Color { Color(nsColor: nsColor(.success)) }
    var warning: Color { Color(nsColor: nsColor(.warning)) }
    var failure: Color { Color(nsColor: nsColor(.failure)) }
    var well: Color { Color(nsColor: nsColor(.well)) }
    var chip: Color { primaryColor.opacity(0.07) }
    var hairline: Color { Color(nsColor: .separatorColor) }

    /// The search field's placeholder: the theme's secondary text, or the
    /// system placeholder color.
    var placeholder: NSColor {
        isCustom(.secondaryText) ? nsColor(.secondaryText) : .placeholderTextColor
    }

    /// Under Increase Contrast, wells, the selection, and keycaps get an
    /// outline, since a subtle fill alone may not set them apart.
    var showsBorders: Bool { increaseContrast }
    var border: Color { primaryColor.opacity(0.6) }

    // MARK: Surface

    /// The surface fill's opacity as drawn. Reduce Transparency and
    /// Increase Contrast make a drawn fill opaque; with no fill, the system
    /// material applies both settings itself.
    var surfaceOpacity: Double {
        theme.surfaceOpacity > 0 && (reduceTransparency || increaseContrast) ? 1 : theme.surfaceOpacity
    }

    /// The fill over the glass, or nil for glass alone.
    var surfaceFill: Color? {
        surfaceOpacity > 0 ? Color(nsColor: nsColor(.surface)).opacity(surfaceOpacity) : nil
    }

    // MARK: Metrics

    var textScale: CGFloat { CGFloat(textSizes.interface.scale) }

    /// A size designed at the standard text size, scaled to the chosen one.
    func scaled(_ value: CGFloat) -> CGFloat {
        (value * textScale).rounded()
    }

    /// The system font at a size designed for the standard text size.
    func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * textScale, weight: weight, design: design)
    }

    var searchFont: NSFont { .systemFont(ofSize: 20 * textScale) }

    /// The size for small controls such as option pickers, which draw their
    /// own text: one step up for each larger text size.
    var controlSize: ControlSize {
        switch textSizes.interface {
        case .small, .standard: .small
        case .large: .regular
        case .extraLarge: .large
        }
    }

    var cornerRadius: CGFloat { CGFloat(theme.cornerRadius) }

    /// A corner radius designed for the standard 18-point panel, kept in
    /// proportion to the theme's.
    func radius(_ base: CGFloat) -> CGFloat {
        base * cornerRadius / CGFloat(PaletteTheme.defaultCornerRadius)
    }

    var panelWidth: CGFloat { scaled(Theme.panelWidth) }
    var searchHeight: CGFloat { scaled(Theme.searchHeight) }
    var toolHeight: CGFloat { scaled(Theme.toolHeight) }

    /// Whether a panel `width` points wide stacks editors and results.
    func isNarrow(width: CGFloat) -> Bool {
        width < scaled(Theme.narrowWidth)
    }

    /// The command list's width in a panel `width` points wide: the same
    /// share as at the standard size.
    func listWidth(forPanelWidth width: CGFloat) -> CGFloat {
        (width * Theme.listWidth / Theme.panelWidth).rounded()
    }

    // MARK: Code

    /// The input and result font.
    var codeFont: NSFont {
        CodeFonts.font(family: theme.codeFontFamily, size: CGFloat(textSizes.codeFontSize))
    }

    /// Monospaced interface text, such as field values: the theme's code
    /// typeface at an interface size.
    func codeFont(_ size: CGFloat) -> Font {
        Font(CodeFonts.font(family: theme.codeFontFamily, size: size * textScale) as CTFont)
    }

    /// Room for `lines` lines of result text, insets included, never less
    /// than the standard layout gave one or two lines.
    func resultHeight(lines: Int) -> CGFloat {
        let font = codeFont
        let line = (font.ascender - font.descender + font.leading) * Theme.codeLineHeight
        let standard: CGFloat = lines <= 1 ? 46 : 66
        return max(standard, (line * CGFloat(lines) + 28).rounded(.up))
    }
}

private struct PaletteStyleKey: EnvironmentKey {
    static let defaultValue = PaletteStyle.standard
}

private struct PalettePreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var paletteStyle: PaletteStyle {
        get { self[PaletteStyleKey.self] }
        set { self[PaletteStyleKey.self] = newValue }
    }

    /// Whether the palette is the theme preview in Settings, where its
    /// text views must not take focus or edit.
    var isPalettePreview: Bool {
        get { self[PalettePreviewKey.self] }
        set { self[PalettePreviewKey.self] = newValue }
    }
}
