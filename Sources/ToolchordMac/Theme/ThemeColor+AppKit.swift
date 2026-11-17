import AppKit
import ToolchordTheme

extension NSColor {
    convenience init(theme color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    /// A color that resolves to `light` or `dark` with the appearance it is
    /// drawn in, high-contrast variants included.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDarkAppearance ? dark : light
        }
    }
}

extension NSAppearance {
    var isDarkAppearance: Bool {
        let match = bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
    }
}

extension ThemeColor {
    /// `nsColor` in sRGB, rounded to the 8 bits a theme stores, so a color
    /// well's value compares equal to the same color read back from a
    /// preset or user defaults. Nil for a color with no sRGB value, such as
    /// a pattern.
    init?(nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self = ThemeColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).rounded
    }
}
