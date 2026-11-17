import Foundation

/// The palette's look: everything a preset sets and Copy Theme shares.
/// Text sizes are separate (`ThemeTextSizes`), so trying a look never
/// changes how large someone needs their text.
///
/// Values arrive from user defaults and the clipboard, which can be
/// hand-edited or written by another version, so nothing here is trusted:
/// decoding skips values it can't read, and `sanitized` keeps the rest
/// within what the renderer supports.
public struct PaletteTheme: Sendable, Hashable {
    /// Bounds on what a theme may ask the renderer to draw.
    public enum Limit {
        public static let surfaceOpacity: ClosedRange<Double> = 0...1
        public static let cornerRadius: ClosedRange<Double> = 0...28
        public static let fontFamilyLength = 128
    }

    public static let defaultCornerRadius: Double = 18

    /// The look Toolchord ships with: the system appearance, colors, and
    /// glass, as the palette looked before themes.
    public static let standard = PaletteTheme()

    public var appearance: ThemeAppearance
    /// The colors this theme sets; a missing role is automatic. Always
    /// empty for the system appearance (see `sanitized`).
    public var colors: [ThemeColorRole: ThemeColor]
    /// How much the surface color covers the system glass behind it: 0
    /// shows the glass alone, 1 is a solid panel. With an automatic surface
    /// the color is the system window background, which follows light and dark.
    public var surfaceOpacity: Double
    /// The panel's corner radius in points. Wells, rows, and chips keep
    /// their proportions to it.
    public var cornerRadius: Double
    /// A monospaced font family for input and results. Nil, or a family
    /// this Mac doesn't have, draws the system's monospaced font (SF Mono).
    public var codeFontFamily: String?

    public init(
        appearance: ThemeAppearance = .system,
        colors: [ThemeColorRole: ThemeColor] = [:],
        surfaceOpacity: Double = 0,
        cornerRadius: Double = PaletteTheme.defaultCornerRadius,
        codeFontFamily: String? = nil
    ) {
        self.appearance = appearance
        self.colors = colors
        self.surfaceOpacity = surfaceOpacity
        self.cornerRadius = cornerRadius
        self.codeFontFamily = codeFontFamily
    }

    public subscript(role: ThemeColorRole) -> ThemeColor? {
        get { colors[role] }
        set { colors[role] = newValue }
    }

    /// The tones a theme is drawn in: its pinned tone, or both for the
    /// system appearance.
    public var tones: [ThemeTone] {
        appearance.pinnedTone.map { [$0] } ?? ThemeTone.allCases
    }

    /// This theme within what the renderer supports. The system appearance
    /// drops every custom color, because one fixed color can't stay
    /// legible in both light and dark. Numbers are clamped and rounded to
    /// the precision the editor offers, so a value dragged back to a
    /// preset's compares equal to it; a value that is not a number takes
    /// the standard theme's.
    public var sanitized: PaletteTheme {
        var result = self
        if appearance == .system { result.colors = [:] }
        result.surfaceOpacity = Self.clamp(surfaceOpacity, to: Limit.surfaceOpacity, stepsPerUnit: 100, fallback: Self.standard.surfaceOpacity)
        result.cornerRadius = Self.clamp(cornerRadius, to: Limit.cornerRadius, stepsPerUnit: 1, fallback: Self.defaultCornerRadius)
        let family = codeFontFamily?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.codeFontFamily = family.flatMap { $0.isEmpty || $0.count > Limit.fontFamilyLength ? nil : $0 }
        return result
    }

    /// Rounds by dividing, not multiplying by the step: 55 / 100 is exactly
    /// the double a `0.55` literal makes, while 55 * 0.01 is not.
    private static func clamp(_ value: Double, to range: ClosedRange<Double>, stepsPerUnit: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        let rounded = (value * stepsPerUnit).rounded() / stepsPerUnit
        return min(range.upperBound, max(range.lowerBound, rounded))
    }
}
