/// A color a theme can set. A role the theme leaves out is automatic: it
/// draws the system's color (accent, surface, text) or Toolchord's own
/// default (syntax and status colors), which adapt to light and dark.
///
/// Raw values are the keys of a stored or shared theme: renaming a case
/// drops that color from every saved theme.
public enum ThemeColorRole: String, Sendable, CaseIterable, Codable, Identifiable {
    case accent
    case surface
    case well
    case text
    case secondaryText
    case code
    case keys
    case strings
    case numbers
    case literals
    case punctuation
    case comments
    case success
    case warning
    case failure

    public var id: String { rawValue }

    /// Where the editor lists a role.
    public enum Group: Sendable, CaseIterable {
        case interface
        case code
        case status
    }

    /// What a role is drawn as, which decides its contrast minimum.
    public enum Kind: Sendable {
        /// Other roles are drawn on it; it has no minimum of its own.
        case background
        /// Read as text: 4.5:1, or 7:1 under Increase Contrast.
        case text
        /// Glyphs that structure text, such as JSON punctuation: 3:1, or
        /// 4.5:1 under Increase Contrast.
        case graphic
        /// Fills and glyphs that are not text, such as the selection and
        /// the selected tool's icon: 3:1, or 4.5:1 under Increase Contrast.
        case component
    }

    public var label: String {
        switch self {
        case .accent: "Accent"
        case .surface: "Surface"
        case .well: "Wells"
        case .text: "Text"
        case .secondaryText: "Secondary text"
        case .code: "Code text"
        case .keys: "Keys and tags"
        case .strings: "Strings"
        case .numbers: "Numbers and attributes"
        case .literals: "Literals"
        case .punctuation: "Punctuation"
        case .comments: "Comments"
        case .success: "Success"
        case .warning: "Warning"
        case .failure: "Failure"
        }
    }

    /// What the role colors, for the editor's help text.
    public var summary: String {
        switch self {
        case .accent: "The selection, the selected tool's icon, and the Copy button"
        case .surface: "The panel behind everything"
        case .well: "The boxes around input, results, and fields"
        case .text: "Titles, list rows, and field values"
        case .secondaryText: "Labels, hints, and summaries"
        case .code: "Plain text in the editor and results"
        case .keys: "JSON keys and XML tag names"
        case .strings: "JSON strings and XML attribute values"
        case .numbers: "JSON numbers and XML attribute names"
        case .literals: "true, false, null, CDATA, and declarations"
        case .punctuation: "Brackets, colons, commas, and tag delimiters"
        case .comments: "XML comments"
        case .success: "Valid results and passing checks"
        case .warning: "Warnings and unsupported input"
        case .failure: "Errors"
        }
    }

    public var group: Group {
        switch self {
        case .accent, .surface, .well, .text, .secondaryText: .interface
        case .code, .keys, .strings, .numbers, .literals, .punctuation, .comments: .code
        case .success, .warning, .failure: .status
        }
    }

    public var kind: Kind {
        switch self {
        case .surface, .well: .background
        case .accent: .component
        case .punctuation: .graphic
        case .text, .secondaryText, .code, .keys, .strings, .numbers, .literals, .comments, .success, .warning, .failure: .text
        }
    }
}
