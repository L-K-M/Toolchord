/// How large the palette draws text. These sizes belong to the person
/// reading, not to a look: applying a preset or a pasted theme keeps them,
/// and only Reset to Default changes them.
public struct ThemeTextSizes: Sendable, Hashable {
    /// Point sizes the code font may take, for the input editor and results.
    public static let codeFontSizes: ClosedRange<Double> = 10...22
    public static let defaultCodeFontSize: Double = 12

    public static let standard = ThemeTextSizes(codeFontSize: defaultCodeFontSize, interface: .standard)

    /// Whole points within `codeFontSizes`.
    public var codeFontSize: Double {
        didSet { codeFontSize = Self.clampedCodeFontSize(codeFontSize) }
    }

    public var interface: InterfaceTextSize

    public init(codeFontSize: Double, interface: InterfaceTextSize) {
        self.codeFontSize = Self.clampedCodeFontSize(codeFontSize)
        self.interface = interface
    }

    /// `value` rounded to whole points and kept within `codeFontSizes`; a
    /// value that is not a number takes the default.
    public static func clampedCodeFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultCodeFontSize }
        return min(codeFontSizes.upperBound, max(codeFontSizes.lowerBound, value.rounded()))
    }
}
