import Foundation

/// The outcome of evaluating one command against one input snapshot.
///
/// Only ``success(_:)`` is copyable. A successful empty `primaryText` is a
/// valid, copyable result: never use non-empty text as the validity test.
/// "Pending" is session state, not a tool outcome.
public enum ToolResult: Sendable, Hashable {
    /// The command needs attached input. The message tells the user what to paste.
    case needsInput(String)
    case success(ToolOutput)
    /// The input is malformed for this command. Copying is disabled.
    case invalid(ToolDiagnostic)
    /// The input uses a feature this release deliberately does not handle,
    /// such as an XML document type declaration or an encrypted JWT.
    case unsupported(String)
    /// The input, output, or nesting exceeds ``ToolLimits``. No partial result.
    case tooLarge(String)

    /// Returned when ``ToolRequest/cancellation`` reports cancellation. The
    /// session never publishes it.
    public static let cancelled = ToolResult.unsupported("Evaluation was cancelled.")

    public var output: ToolOutput? {
        if case .success(let output) = self { return output }
        return nil
    }

    public var isSuccess: Bool { output != nil }

    /// A one-line description of a non-successful result.
    public var problem: String? {
        switch self {
        case .success: nil
        case .needsInput(let message), .unsupported(let message), .tooLarge(let message): message
        case .invalid(let diagnostic): diagnostic.description
        }
    }
}

/// How the UI should present a successful result.
public enum ResultPresentation: Sendable, Hashable {
    /// Show `primaryText` as the result. Fields, if any, appear below it.
    case text
    /// Show `fields` as labeled rows; `primaryText` is their serialized form
    /// (for example, the ordered query parameters as JSON).
    case fields
}

/// Lexical hint for coloring a text result.
public enum SyntaxKind: Sendable, Hashable {
    case plain
    case json
    case xml
}

public struct ToolOutput: Sendable, Hashable {
    /// The exact text that Copy & Close places on the clipboard.
    public var primaryText: String
    /// A short validity or kind label shown beside the preview, such as
    /// "Valid JSON", "Well-formed XML", or "UUID v4".
    public var status: String
    /// How the status reads: `.success` for a clean result, `.warning` for a
    /// result that needs attention (such as an unverified JWT signature).
    public var statusTone: ResultField.Tone
    public var presentation: ResultPresentation
    public var syntax: SyntaxKind
    /// Secondary values with their own Copy controls. Field Copy keeps the
    /// panel open.
    public var fields: [ResultField]
    /// Non-fatal issues, such as duplicate JSON member names.
    public var warnings: [String]
    /// A color to show beside the result, for color conversions.
    public var swatch: ColorSwatch?
    /// How copies of the primary text and fields are written.
    public var sensitivity: ClipboardSensitivity

    public init(
        primaryText: String,
        status: String,
        presentation: ResultPresentation = .text,
        syntax: SyntaxKind = .plain,
        fields: [ResultField] = [],
        warnings: [String] = [],
        swatch: ColorSwatch? = nil,
        statusTone: ResultField.Tone = .success,
        sensitivity: ClipboardSensitivity = .normal
    ) {
        self.primaryText = primaryText
        self.status = status
        self.statusTone = statusTone
        self.presentation = presentation
        self.syntax = syntax
        self.fields = fields
        self.warnings = warnings
        self.swatch = swatch
        self.sensitivity = sensitivity
    }
}

/// An sRGB color with components in 0...1.
public struct ColorSwatch: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct ResultField: Sendable, Hashable, Identifiable {
    public enum Tone: Sendable, Hashable {
        case normal
        case success
        case warning
    }

    /// Unique within one output.
    public var id: String
    public var label: String
    public var value: String
    /// Secondary text beneath or beside the value, such as a readable date.
    public var note: String?
    public var tone: Tone
    public var isCopyable: Bool
    public var isMonospaced: Bool

    public init(
        id: String,
        label: String,
        value: String,
        note: String? = nil,
        tone: Tone = .normal,
        isCopyable: Bool = true,
        isMonospaced: Bool = true
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.note = note
        self.tone = tone
        self.isCopyable = isCopyable
        self.isMonospaced = isMonospaced
    }
}

/// A malformed-input report. `location`, when present, points into the
/// original input.
public struct ToolDiagnostic: Sendable, Hashable, Error, CustomStringConvertible {
    public var message: String
    public var location: TextLocation?

    public init(_ message: String, at location: TextLocation? = nil) {
        self.message = message
        self.location = location
    }

    public var description: String {
        guard let location else { return message }
        return "\(message) (\(location))"
    }
}

/// A one-based position in text. Columns count Unicode scalars; CR, LF, and
/// CRLF each count as one line break.
public struct TextLocation: Sendable, Hashable, CustomStringConvertible {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public var description: String { "line \(line), column \(column)" }
}
