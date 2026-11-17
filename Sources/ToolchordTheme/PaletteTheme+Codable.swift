import Foundation

/// The stored and shared form of a theme: one JSON object.
///
/// ```json
/// {
///   "appearance" : "dark",
///   "codeFont" : "Menlo",
///   "colors" : { "accent" : "#FF2E97", "surface" : "#1A1033" },
///   "cornerRadius" : 14,
///   "surfaceOpacity" : 1,
///   "toolchordTheme" : 1
/// }
/// ```
///
/// Decoding is lenient per value: an unreadable color loses that color,
/// not the theme, and a missing or unreadable setting takes the standard
/// theme's. `toolchordTheme` is the format version; Paste Theme requires it,
/// so other JSON on the clipboard isn't mistaken for a theme.
extension PaletteTheme: Codable {
    public static let formatVersion = 1

    private enum CodingKeys: String, CodingKey {
        case format = "toolchordTheme"
        case appearance
        case colors
        case surfaceOpacity
        case cornerRadius
        case codeFont
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        var colors: [ThemeColorRole: ThemeColor] = [:]
        if let stored: [String: Lenient<ThemeColor>] = value(.colors) {
            for (key, entry) in stored {
                guard let role = ThemeColorRole(rawValue: key), let color = entry.value else { continue }
                colors[role] = color
            }
        }
        let theme = PaletteTheme(
            appearance: value(.appearance) ?? Self.standard.appearance,
            colors: colors,
            surfaceOpacity: value(.surfaceOpacity) ?? Self.standard.surfaceOpacity,
            cornerRadius: value(.cornerRadius) ?? Self.standard.cornerRadius,
            codeFontFamily: value(.codeFont)
        )
        self = theme.sanitized
    }

    public func encode(to encoder: Encoder) throws {
        let theme = sanitized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .format)
        try container.encode(theme.appearance, forKey: .appearance)
        let colors = Dictionary(uniqueKeysWithValues: theme.colors.map { ($0.key.rawValue, $0.value) })
        try container.encode(colors, forKey: .colors)
        try container.encode(theme.surfaceOpacity, forKey: .surfaceOpacity)
        try container.encode(theme.cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(theme.codeFontFamily, forKey: .codeFont)
    }
}

extension PaletteTheme {
    /// Why Paste Theme didn't apply what was on the clipboard.
    public enum ImportError: Error, Sendable, Equatable, CustomStringConvertible {
        case tooLong
        case notATheme

        public var description: String {
            switch self {
            case .tooLong: "The clipboard holds more text than a Toolchord theme."
            case .notATheme: "The clipboard doesn't hold a Toolchord theme. Copy one with Copy Theme first."
            }
        }
    }

    /// Longer clipboard text is rejected before parsing. A theme with every
    /// color set is under 1 KB.
    public static let maximumImportBytes = 16 * 1024

    /// Pretty, key-sorted JSON, for the clipboard and user defaults.
    public var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // A sanitized theme holds only finite numbers, which always encode.
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Reads a theme Toolchord stored. Text that is not a JSON object
    /// yields nil, so the caller falls back to the standard theme.
    public init?(storedText: String) {
        guard let data = storedText.data(using: .utf8), let theme = try? JSONDecoder().decode(PaletteTheme.self, from: data) else {
            return nil
        }
        self = theme
    }

    /// Reads a theme someone copied with Copy Theme. Unlike stored text,
    /// it must carry the `toolchordTheme` version.
    public static func imported(from text: String) -> Result<PaletteTheme, ImportError> {
        guard text.utf8.count <= maximumImportBytes else { return .failure(.tooLong) }
        let data = Data(text.utf8)
        guard (try? JSONDecoder().decode(FormatMarker.self, from: data)) != nil,
              let theme = try? JSONDecoder().decode(PaletteTheme.self, from: data) else {
            return .failure(.notATheme)
        }
        return .success(theme)
    }

    private struct FormatMarker: Decodable {
        let toolchordTheme: Int
    }
}

/// A stored value that may be unreadable, so one bad entry of a dictionary
/// doesn't fail the rest.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
