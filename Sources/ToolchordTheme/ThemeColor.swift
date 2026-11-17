import Foundation

/// An opaque sRGB color. Themes are plain data so their contrast can be
/// checked without AppKit; the Mac layer turns them into `NSColor`.
///
/// Stored and shared as `#RRGGBB`: readable in `defaults read` and in a
/// copied theme, and a malformed value is rejected rather than turned into
/// some other color.
public struct ThemeColor: Sendable, Hashable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Components outside 0...1 are clamped, and NaN becomes 0, so every
    /// color formats as a `#RRGGBB` string that parses again.
    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
    }

    /// `ThemeColor(0xFF2E97)`. Preset colors are integer literals, so a
    /// malformed hex string cannot reach a shipped theme.
    public init(_ rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Parses `#RRGGBB` or the shorthand `#RGB`, with or without the `#`,
    /// ignoring case and surrounding whitespace. Anything else, including a
    /// color with alpha, is rejected: theme colors are opaque.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        // `UInt32(_:radix:)` alone would accept a leading "+".
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded = digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : String(digits)
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        self.init(value)
    }

    public static let black = ThemeColor(0x000000)
    public static let white = ThemeColor(0xFFFFFF)

    /// `#RRGGBB` in uppercase.
    public var hex: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    public var description: String { hex }

    /// This color rounded to the 8 bits per channel that `hex` stores, so a
    /// computed color compares equal to the same color read back.
    public var rounded: ThemeColor {
        ThemeColor(UInt32(Self.byte(red)) << 16 | UInt32(Self.byte(green)) << 8 | UInt32(Self.byte(blue)))
    }

    // MARK: Contrast

    /// WCAG 2.x relative luminance: 0 for black, 1 for white.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio, 1...21.
    public func contrast(with other: ThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This color painted at `opacity` over `background`, composited in
    /// sRGB as Core Graphics composites non-linear sRGB layers.
    public func blended(over background: ThemeColor, opacity: Double) -> ThemeColor {
        let alpha = Self.unit(opacity)
        return ThemeColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha)
        )
    }

    /// Black or white, whichever reads better on this color. One of the
    /// two always reaches at least 4.58:1.
    public var readableForeground: ThemeColor {
        contrast(with: .black) >= contrast(with: .white) ? .black : .white
    }

    /// The lowest contrast this color has with any of `backgrounds`.
    public func worstContrast(against backgrounds: [ThemeColor]) -> Double {
        backgrounds.map(contrast(with:)).min() ?? 21
    }

    /// This color moved the least distance toward black or white that
    /// reaches `minimum` contrast with every one of `backgrounds`. It keeps
    /// its hue, so a raised theme still looks like itself.
    ///
    /// The direction is whichever of black and white contrasts better with
    /// the backgrounds. Along it, a color that starts below the minimum
    /// stays below until some point and stays above after it, so a binary
    /// search finds the smallest step. When even black or white cannot
    /// reach the minimum (a mid-gray background), the result is that end.
    public func raisingContrast(to minimum: Double, against backgrounds: [ThemeColor]) -> ThemeColor {
        guard !backgrounds.isEmpty, worstContrast(against: backgrounds) < minimum else { return self }
        let target = ThemeColor.black.worstContrast(against: backgrounds) >= ThemeColor.white.worstContrast(against: backgrounds)
            ? ThemeColor.black : ThemeColor.white
        guard target.worstContrast(against: backgrounds) >= minimum else { return target }
        var low = 0.0
        var high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if target.blended(over: self, opacity: middle).worstContrast(against: backgrounds) >= minimum {
                high = middle
            } else {
                low = middle
            }
        }
        return target.blended(over: self, opacity: high)
    }

    // MARK: Helpers

    private static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : min(1, max(0, value))
    }

    private static func byte(_ component: Double) -> Int {
        Int((unit(component) * 255).rounded())
    }
}

/// Stored as `#RRGGBB`, so a saved or shared theme stays readable and a
/// malformed value fails to decode instead of becoming another color.
extension ThemeColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ThemeColor(hex: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a #RRGGBB color, got \(text.prefix(16))"
            )
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
