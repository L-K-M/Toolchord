import Foundation

/// A color Toolchord draws that misses its contrast minimum on one of the
/// backgrounds it is drawn on. Only the worst background is reported.
public struct ContrastIssue: Sendable, Hashable, CustomStringConvertible {
    public let role: ThemeColorRole
    public let tone: ThemeTone
    public let foreground: ThemeColor
    public let background: ThemeColor
    public let ratio: Double
    public let minimum: Double

    public init(role: ThemeColorRole, tone: ThemeTone, foreground: ThemeColor, background: ThemeColor, ratio: Double, minimum: Double) {
        self.role = role
        self.tone = tone
        self.foreground = foreground
        self.background = background
        self.ratio = ratio
        self.minimum = minimum
    }

    /// "Strings: 3.2:1, needs 4.5:1".
    public var summary: String {
        "\(role.label): \(Self.format(ratio)):1, needs \(Self.format(minimum)):1"
    }

    public var description: String {
        "\(role.rawValue) \(foreground) on \(background) in \(tone.rawValue) is \(Self.format(ratio)):1, needs \(Self.format(minimum)):1"
    }

    private static func format(_ ratio: Double) -> String {
        String(format: "%.1f", (ratio * 10).rounded(.down) / 10)
    }
}
