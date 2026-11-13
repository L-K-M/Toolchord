import Foundation

/// Guesses what attached text is, cheaply and without validating it fully.
///
/// Detection only orders suggestions: JSON-like and XML-like text still
/// suggests the JSON and XML commands when malformed, so validation can
/// report the error. Work is bounded: token checks only run on single-line
/// input up to ``tokenLimit`` bytes, and pattern scans look at a prefix.
public enum InputDetector {
    /// Largest single-line token checked for JWT, Base64, URL, and similar kinds.
    public static let tokenLimit = 64 * 1024
    /// Prefix scanned for HTML entities and escape sequences.
    public static let scanLimit = 64 * 1024

    public static func profile(for input: ToolInput) -> InputProfile {
        guard let text = input.text else { return .none }
        return profile(for: text)
    }

    /// Profiles `text`. Text larger than `maxBytes` is reported as plain
    /// text without scanning it, so oversized pastes stay responsive; the
    /// commands then reject it with their input-limit message.
    public static func profile(for text: String, maxBytes: Int = ToolLimits.standard.maxInputBytes) -> InputProfile {
        let utf8 = text.utf8
        let byteCount = utf8.count
        if byteCount > maxBytes {
            return InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: byteCount, lineCount: 0, isBlank: false)
        }
        let lineCount = countLines(utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Blank, but possibly only non-breaking spaces or line separators.
            var kinds: Set<InputKind> = [.text]
            if prefix(of: text, maxBytes: scanLimit).unicodeScalars.contains(where: PlainTextTools.isSpecial) {
                kinds.insert(.specialCharacters)
            }
            return InputProfile(isAttached: true, kinds: kinds, primaryKind: .text, byteCount: byteCount, lineCount: lineCount, isBlank: true)
        }

        var kinds: Set<InputKind> = [.text]
        if lineCount > 1 { kinds.insert(.multiline) }

        let first = trimmed.unicodeScalars.first!
        let last = trimmed.unicodeScalars.last!
        if first == "{" || (first == "[" && startsLikeJSONArray(trimmed)) { kinds.insert(.json) }
        if first == "<" && trimmed.contains(">") { kinds.insert(.xml) }
        if first == "\"" && last == "\"" && trimmed.unicodeScalars.count >= 2 { kinds.insert(.jsonStringLiteral) }

        let isSingleToken = trimmed.utf8.count <= tokenLimit && !trimmed.unicodeScalars.contains { $0.properties.isWhitespace }
        if isSingleToken {
            detectToken(trimmed, into: &kinds)
        } else if lineCount == 1 && trimmed.utf8.count <= 200 {
            if isDateTime(trimmed) { kinds.insert(.dateTime) }
            if isColor(trimmed) { kinds.insert(.color) }
            if !kinds.contains(.color) && looksLikeWords(trimmed) { kinds.insert(.words) }
        }

        let sample = prefix(of: text, maxBytes: scanLimit)
        if !kinds.contains(.json) && kinds.isDisjoint(with: specificTokenKinds) {
            let isMarkdown = MarkupDetector.isMarkdown(sample)
            if isMarkdown { kinds.insert(.markdown) }
            if MarkupDetector.isHTML(sample, startsWithMarkup: first == "<", isMarkdown: isMarkdown) {
                kinds.insert(.html)
            }
        }
        if sample.unicodeScalars.contains(where: PlainTextTools.isSpecial) { kinds.insert(.specialCharacters) }
        if containsHTMLEntity(sample) { kinds.insert(.htmlEntities) }
        if containsBackslashEscape(sample) { kinds.insert(.escapedText) }
        if !kinds.contains(.percentEncoded) && !kinds.contains(.url) && containsPercentEscape(sample) {
            kinds.insert(.percentEncoded)
        }

        return InputProfile(
            isAttached: true,
            kinds: kinds,
            primaryKind: primaryKind(of: kinds),
            byteCount: byteCount,
            lineCount: lineCount,
            isBlank: false
        )
    }

    /// Kinds of a single token (URLs, numbers, encodings) that rule out
    /// reading the text as Markdown or HTML.
    private static let specificTokenKinds: Set<InputKind> = [
        .jwt, .url, .queryString, .uuid, .dateTime, .unixTime, .color, .hexColor, .base64, .base64URL, .number, .hex,
    ]

    /// `[` followed by `]` or something that can start a JSON value, so
    /// Markdown such as `[docs](https://…)` and prose in brackets aren't taken
    /// for JSON. Malformed arrays such as `[1,` still are.
    private static func startsLikeJSONArray(_ text: String) -> Bool {
        let rest = text.unicodeScalars.dropFirst().drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let next = rest.first else { return true }
        if "{[]\"-0123456789".unicodeScalars.contains(next) { return true }
        let word = String(String.UnicodeScalarView(rest.prefix(5)))
        return word.hasPrefix("true") || word.hasPrefix("false") || word.hasPrefix("null")
    }

    // MARK: - Token kinds

    private static func detectToken(_ token: String, into kinds: inout Set<InputKind>) {
        let scalars = Array(token.unicodeScalars)
        if isJWT(token) { kinds.insert(.jwt) }
        if hasURLScheme(scalars) { kinds.insert(.url) }
        if isQueryString(token) { kinds.insert(.queryString) }
        if containsPercentEscape(Substring(token)) { kinds.insert(.percentEncoded) }
        if isUUID(scalars) { kinds.insert(.uuid) }
        if isDateTime(token) { kinds.insert(.dateTime) }
        if isColor(token) {
            kinds.insert(.color)
            if scalars.first == "#" { kinds.insert(.hexColor) }
        }

        let unsigned = scalars.first == "-" || scalars.first == "+" ? Array(scalars.dropFirst()) : scalars
        let digits = unsigned.prefix { $0.properties.numericType == .decimal && $0.isASCII }
        if !unsigned.isEmpty && digits.count == unsigned.count {
            kinds.insert(.number)
            if (9...13).contains(digits.count) { kinds.insert(.unixTime) }
        } else if isDecimalWithFraction(unsigned) {
            kinds.insert(.number)
            let integerDigits = unsigned.prefix { $0 != "." }.count
            if (9...13).contains(integerDigits) { kinds.insert(.unixTime) }
        }
        if isPrefixedNumber(token) { kinds.insert(.number) }
        if isHex(token) { kinds.insert(.hex) }

        if !kinds.contains(.jwt) && !kinds.contains(.url) && !kinds.contains(.uuid) && !kinds.contains(.number) && !kinds.contains(.hex) {
            switch base64Kind(scalars) {
            case .standard: kinds.insert(.base64)
            case .url: kinds.insert(.base64URL)
            case nil: break
            }
        }
        let isEncoded = kinds.contains(.url) || kinds.contains(.jwt) || kinds.contains(.base64) || kinds.contains(.base64URL)
        if !isEncoded && looksLikeWords(token) { kinds.insert(.words) }
    }

    private static func isJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 5 else { return false }
        guard parts[0].count >= 4, parts.dropLast().allSatisfy({ !$0.isEmpty }) else { return false }
        guard parts.allSatisfy({ $0.unicodeScalars.allSatisfy(isBase64URLScalar) }) else { return false }
        // The protected header must decode to a JSON object.
        guard let header = decodeBase64URLPrefix(parts[0]) else { return false }
        return header.first == UInt8(ascii: "{")
    }

    private static func decodeBase64URLPrefix(_ segment: Substring) -> [UInt8]? {
        var text = String(segment.prefix(64)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text = String(text.prefix(text.count - text.count % 4))
        guard !text.isEmpty, let data = Data(base64Encoded: text) else { return nil }
        let bytes = [UInt8](data)
        let firstNonSpace = bytes.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return firstNonSpace.map { [$0] }
    }

    private static func hasURLScheme(_ scalars: [Unicode.Scalar]) -> Bool {
        guard let first = scalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        var index = 1
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == ":" { break }
            guard scalar.isASCII, scalar.properties.isAlphabetic || scalar.properties.numericType == .decimal || scalar == "+" || scalar == "-" || scalar == "." else {
                return false
            }
            index += 1
        }
        guard index < scalars.count, index + 2 < scalars.count else { return false }
        return scalars[index + 1] == "/" && scalars[index + 2] == "/"
    }

    private static func isQueryString(_ token: String) -> Bool {
        var body = Substring(token)
        if body.hasPrefix("?") { body = body.dropFirst() }
        guard body.contains("=") else { return false }
        let pairs = body.split(separator: "&", omittingEmptySubsequences: true)
        guard !pairs.isEmpty else { return false }
        // Every key must be plausible, so text that merely contains `=` and
        // `&` (a Markdown link to a URL with a query) isn't taken for one.
        return pairs.allSatisfy { pair in
            let key = pair.prefix { $0 != "=" }
            return !key.isEmpty && key.unicodeScalars.allSatisfy {
                $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType == .decimal || "_-.[]%+$~*!".unicodeScalars.contains($0))
            }
        }
    }

    private static func isUUID(_ scalars: [Unicode.Scalar]) -> Bool {
        let hyphenPositions: Set<Int> = [8, 13, 18, 23]
        if scalars.count == 36 {
            for (index, scalar) in scalars.enumerated() {
                if hyphenPositions.contains(index) {
                    guard scalar == "-" else { return false }
                } else if !isHexScalar(scalar) {
                    return false
                }
            }
            return true
        }
        if scalars.count == 38, scalars.first == "{", scalars.last == "}" {
            return isUUID(Array(scalars.dropFirst().dropLast()))
        }
        return false
    }

    /// RFC 3339-like date or date-time, with or without an offset. Commands
    /// enforce the exact accepted grammar.
    static func isDateTime(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        func digits(_ range: Range<Int>) -> Bool {
            range.upperBound <= scalars.count && range.allSatisfy { scalars[$0].isASCII && scalars[$0].properties.numericType == .decimal }
        }
        guard scalars.count >= 10, digits(0..<4), scalars[4] == "-", digits(5..<7), scalars[7] == "-", digits(8..<10) else {
            return false
        }
        if scalars.count == 10 { return true }
        guard scalars.count >= 16, scalars[10] == "T" || scalars[10] == "t" || scalars[10] == " ", digits(11..<13), scalars[13] == ":", digits(14..<16) else {
            return false
        }
        return true
    }

    private static func isColor(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        if scalars.first == "#" {
            let hex = scalars.dropFirst()
            return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy(isHexScalar)
        }
        let lower = token.lowercased()
        return ["rgb(", "rgba(", "hsl(", "hsla("].contains { lower.hasPrefix($0) } && lower.hasSuffix(")")
    }

    private static func isDecimalWithFraction(_ scalars: [Unicode.Scalar]) -> Bool {
        guard let dot = scalars.firstIndex(of: "."), dot > 0, dot < scalars.count - 1 else { return false }
        let isDigit: (Unicode.Scalar) -> Bool = { $0.isASCII && $0.properties.numericType == .decimal }
        return scalars[..<dot].allSatisfy(isDigit) && scalars[(dot + 1)...].allSatisfy(isDigit)
    }

    private static func isPrefixedNumber(_ token: String) -> Bool {
        let lower = token.lowercased()
        let body: Substring
        let allowed: (Unicode.Scalar) -> Bool
        if lower.hasPrefix("0x") {
            body = lower.dropFirst(2)
            allowed = isHexScalar
        } else if lower.hasPrefix("0b") {
            body = lower.dropFirst(2)
            allowed = { $0 == "0" || $0 == "1" }
        } else if lower.hasPrefix("0o") {
            body = lower.dropFirst(2)
            allowed = { ("0"..."7").contains($0) }
        } else {
            return false
        }
        let digits = body.unicodeScalars.filter { $0 != "_" }
        return !digits.isEmpty && digits.allSatisfy(allowed)
    }

    /// Hex text with at least one letter digit (pure decimal digits are numbers).
    private static func isHex(_ token: String) -> Bool {
        var body = Substring(token)
        if body.lowercased().hasPrefix("0x") { body = body.dropFirst(2) }
        guard body.count >= 2 else { return false }
        let scalars = body.unicodeScalars
        guard scalars.allSatisfy(isHexScalar) else { return false }
        return token.lowercased().hasPrefix("0x") || scalars.contains { $0.properties.isAlphabetic }
    }

    private enum Base64Alphabet { case standard, url }

    private static func base64Kind(_ scalars: [Unicode.Scalar]) -> Base64Alphabet? {
        guard scalars.count >= 8, !isIdentifier(scalars) else { return nil }
        var hasStandardOnly = false
        var hasURLOnly = false
        var hasDigit = false
        var hasUpper = false
        var hasLower = false
        var paddingStart: Int?
        for (index, scalar) in scalars.enumerated() {
            if scalar == "=" {
                if paddingStart == nil { paddingStart = index }
                continue
            }
            if paddingStart != nil { return nil }
            switch scalar {
            case "A"..."Z": hasUpper = true
            case "a"..."z": hasLower = true
            case "0"..."9": hasDigit = true
            case "+", "/": hasStandardOnly = true
            case "-", "_": hasURLOnly = true
            default: return nil
            }
        }
        if hasStandardOnly && hasURLOnly { return nil }
        let padding = paddingStart.map { scalars.count - $0 } ?? 0
        guard padding <= 2 else { return nil }
        // Plain words ("password", "localhost") are valid Base64 by alphabet;
        // require evidence such as mixed case with digits, symbols, or padding.
        let looksEncoded = hasStandardOnly || hasURLOnly || padding > 0 || (hasUpper && hasLower && hasDigit)
        guard looksEncoded else { return nil }
        if hasURLOnly { return .url }
        if padding > 0 || hasStandardOnly { return scalars.count % 4 == 0 ? .standard : nil }
        return scalars.count % 4 == 0 ? .standard : .url
    }

    // Identifier spelling shares the Base64 alphabets; keep case-conversion
    // suggestions available when word structure is stronger evidence.
    private static func isIdentifier(_ scalars: [Unicode.Scalar]) -> Bool {
        var hasUpper = false
        var hasLower = false
        for scalar in scalars {
            switch scalar {
            case "A"..."Z": hasUpper = true
            case "a"..."z": hasLower = true
            case "0"..."9", "-", "_": break
            default: return false
            }
        }
        if !hasUpper || !hasLower { return true }

        var partStart = 0
        var partCount = 0
        var characterCount = 0
        for index in scalars.indices {
            let scalar = scalars[index]
            let isSeparator = scalar == "-" || scalar == "_"
            let isBoundary = index > partStart && isIdentifierBoundary(scalars, at: index)
            if !isSeparator && !isBoundary { continue }
            if index > partStart {
                guard isIdentifierPart(scalars[partStart..<index]) else { return false }
                partCount += 1
                characterCount += index - partStart
            }
            partStart = isSeparator ? index + 1 : index
        }
        if partStart < scalars.count {
            guard isIdentifierPart(scalars[partStart...]) else { return false }
            partCount += 1
            characterCount += scalars.count - partStart
        }
        return partCount > 0 && characterCount >= 3 * partCount
    }

    private static func isIdentifierBoundary(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard ("A"..."Z").contains(scalars[index]) else { return false }
        let previous = scalars[index - 1]
        if ("a"..."z").contains(previous) || ("0"..."9").contains(previous) { return true }
        return ("A"..."Z").contains(previous)
            && index + 1 < scalars.count && ("a"..."z").contains(scalars[index + 1])
    }

    private static func isIdentifierPart(_ part: ArraySlice<Unicode.Scalar>) -> Bool {
        let afterUpper = part.drop { ("A"..."Z").contains($0) }
        let afterLower = afterUpper.drop { ("a"..."z").contains($0) }
        return !part.isEmpty && afterLower.allSatisfy { ("0"..."9").contains($0) }
    }

    /// A short single line of words or an identifier, such as `user name`,
    /// `userName`, `user-name`, or `Hello, World!`. Characters typical of code
    /// or data (`{ } [ ] < > \\ |` and control characters) rule it out.
    private static func looksLikeWords(_ text: String) -> Bool {
        guard text.utf8.count <= 200 else { return false }
        var letters = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isAlphabetic {
                letters += 1
            } else if "{}[]<>\\|".unicodeScalars.contains(scalar) || scalar.properties.generalCategory == .control {
                return false
            }
        }
        return letters >= 2
    }

    // MARK: - Content scans

    private static func containsHTMLEntity(_ text: Substring) -> Bool {
        var index = text.startIndex
        while let amp = text[index...].firstIndex(of: "&") {
            let rest = text[text.index(after: amp)...].prefix(12)
            if let semicolon = rest.firstIndex(of: ";") {
                let name = rest[..<semicolon]
                if name.count >= 2 {
                    if name.first == "#" {
                        let digits = name.dropFirst()
                        if digits.first == "x" || digits.first == "X" {
                            if digits.count > 1, digits.dropFirst().unicodeScalars.allSatisfy(isHexScalar) { return true }
                        } else if !digits.isEmpty, digits.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.numericType == .decimal }) {
                            return true
                        }
                    } else if name.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType == .decimal) }) {
                        return true
                    }
                }
            }
            index = text.index(after: amp)
        }
        return false
    }

    private static func containsBackslashEscape(_ text: Substring) -> Bool {
        var previousBackslash = false
        for scalar in text.unicodeScalars {
            if previousBackslash {
                if "nrt\"\\/bfu".unicodeScalars.contains(scalar) { return true }
                previousBackslash = false
            } else if scalar == "\\" {
                previousBackslash = true
            }
        }
        return false
    }

    private static func containsPercentEscape(_ text: Substring) -> Bool {
        let scalars = Array(text.unicodeScalars.prefix(scanLimit))
        guard scalars.count >= 3 else { return false }
        for index in 0..<(scalars.count - 2) where scalars[index] == "%" {
            if isHexScalar(scalars[index + 1]) && isHexScalar(scalars[index + 2]) { return true }
        }
        return false
    }

    // MARK: - Helpers

    private static func primaryKind(of kinds: Set<InputKind>) -> InputKind {
        // Base64 outranks query strings: padding "=" only appears at the end
        // of Base64, so text matching both is almost always Base64. A
        // prefixed number such as 0xff is a number before it is hex bytes.
        let priority: [InputKind] = [
            .jwt, .json, .html, .xml, .url, .uuid, .dateTime, .unixTime, .color, .base64URL, .base64, .queryString,
            .number, .hex, .markdown, .percentEncoded, .jsonStringLiteral, .htmlEntities, .escapedText, .words, .multiline, .text,
        ]
        return priority.first { kinds.contains($0) } ?? .text
    }

    private static func countLines(_ utf8: String.UTF8View) -> Int {
        var lines = 1
        var previousWasCR = false
        for byte in utf8 {
            if byte == 0x0A {
                if !previousWasCR { lines += 1 }
                previousWasCR = false
            } else if byte == 0x0D {
                lines += 1
                previousWasCR = true
            } else {
                previousWasCR = false
            }
        }
        return lines
    }

    private static func prefix(of text: String, maxBytes: Int) -> Substring {
        guard text.utf8.count > maxBytes else { return Substring(text) }
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: maxBytes)
        while end > text.startIndex && !text.unicodeScalars.indices.contains(end) {
            end = text.utf8.index(before: end)
        }
        return text[..<end]
    }

    static func isHexScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9", "a"..."f", "A"..."F": true
        default: false
        }
    }

    static func isBase64URLScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
