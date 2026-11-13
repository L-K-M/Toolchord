import Foundation

/// Case conversion and slugs.
public enum CaseTools {

    // MARK: - Commands

    public static let commands: [ToolCommand] = [
        command(
            id: "case.camel",
            title: "Convert to camelCase",
            summary: "Lowercase first word, capitalize the rest",
            aliases: ["camel case", "camelcase", "lower camel case"],
            style: .camel
        ),
        command(
            id: "case.pascal",
            title: "Convert to PascalCase",
            summary: "Capitalize every word, no separators",
            aliases: ["pascal case", "upper camel case", "studly case"],
            style: .pascal
        ),
        command(
            id: "case.snake",
            title: "Convert to snake_case",
            summary: "Lowercase words joined by underscores",
            aliases: ["snake case", "underscore case"],
            style: .snake
        ),
        command(
            id: "case.kebab",
            title: "Convert to kebab-case",
            summary: "Lowercase words joined by hyphens",
            aliases: ["kebab case", "dash case", "hyphen case", "param case"],
            style: .kebab
        ),
        command(
            id: "case.constant",
            title: "Convert to CONSTANT_CASE",
            summary: "Uppercase words joined by underscores",
            aliases: ["constant case", "screaming snake case", "upper snake case", "macro case"],
            style: .constant
        ),
        command(
            id: "case.title",
            title: "Convert to Title Case",
            summary: "Capitalize every word",
            aliases: ["title case", "capitalize words", "headline case"],
            style: .title
        ),
        command(
            id: "case.sentence",
            title: "Convert to Sentence case",
            summary: "Capitalize the first word only",
            aliases: ["sentence case"],
            style: .sentence
        ),
        command(
            id: "case.lower",
            title: "Convert to lowercase",
            summary: "Every letter lowercase",
            aliases: ["lowercase", "lower case", "downcase"],
            style: .lower
        ),
        command(
            id: "case.upper",
            title: "Convert to UPPERCASE",
            summary: "Every letter uppercase",
            aliases: ["uppercase", "upper case", "caps", "upcase"],
            style: .upper
        ),
        command(
            id: "case.slug",
            title: "Convert to Slug",
            summary: "URL-friendly lowercase words",
            aliases: ["slugify", "slug", "url slug", "permalink"],
            style: .slug
        ),
    ]

    // MARK: - Style

    enum Style: Sendable {
        case camel, pascal, snake, kebab, constant, title, sentence, lower, upper, slug
    }

    // MARK: - Command factory

    private static func command(
        id: String,
        title: String,
        summary: String,
        aliases: [String],
        style: Style
    ) -> ToolCommand {
        ToolCommand(
            id: id,
            title: title,
            summary: summary,
            group: .textCase,
            icon: .glyph("Aa"),
            aliases: aliases,
            copyNoun: "text",
            affinity: { profile in profile.isPlainText && profile.has(.words) ? 40 : 0 },
            evaluate: { request in evaluate(request, style: style) }
        )
    }

    // MARK: - Evaluation

    static func evaluate(_ request: ToolRequest, style: Style) -> ToolResult {
        guard let text = request.input.text else {
            return .needsInput("Paste text to convert.")
        }

        let converted: String?
        switch style {
        case .lower:
            converted = convertLower(text, cancellation: request.cancellation)
        case .upper:
            converted = convertUpper(text, cancellation: request.cancellation)
        case .slug:
            converted = convertSlug(text, cancellation: request.cancellation)
        default:
            converted = convertSplit(text, style: style, cancellation: request.cancellation)
        }
        guard let result = converted else { return .cancelled }

        // Check output size limit
        if result.utf8.count > request.limits.maxOutputBytes {
            return .tooLarge(request.limits.outputLimitMessage)
        }

        let status = statusLabel(for: style)
        return .success(ToolOutput(primaryText: result, status: status))
    }

    // MARK: - Status labels

    private static func statusLabel(for style: Style) -> String {
        switch style {
        case .camel: return "camelCase"
        case .pascal: return "PascalCase"
        case .snake: return "snake_case"
        case .kebab: return "kebab-case"
        case .constant: return "CONSTANT_CASE"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .lower: return "lowercase"
        case .upper: return "UPPERCASE"
        case .slug: return "Slug"
        }
    }

    // MARK: - Helpers

    /// Build a String from an array of Unicode.Scalar.
    private static func string(from scalars: [Unicode.Scalar]) -> String {
        String(scalars.map { Character($0) })
    }

    /// Letters, numbers, and combining marks (so a decomposed "é" stays in its word).
    private static func isLetterOrNumber(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return s.properties.isAlphabetic || s.properties.numericType != nil
        }
    }

    private static func isLower(_ s: Unicode.Scalar) -> Bool {
        s.properties.isLowercase
    }

    private static func isUpper(_ s: Unicode.Scalar) -> Bool {
        s.properties.isUppercase
    }

    // MARK: - Line splitting

    /// Splits text into (lineContent, lineBreak) pairs. Each lineBreak is the
    /// exact break sequence ("", "\n", "\r", or "\r\n").
    static func splitLines(_ text: String) -> [(content: String, break: String)] {
        let scalars = Array(text.unicodeScalars)
        var lines: [(String, String)] = []
        var i = 0
        var lineStart = 0

        while i < scalars.count {
            if scalars[i].value == 13, i + 1 < scalars.count, scalars[i + 1].value == 10 {
                // CRLF
                let content = string(from: Array(scalars[lineStart..<i]))
                lines.append((content, "\r\n"))
                i += 2
                lineStart = i
            } else if scalars[i].value == 10 || scalars[i].value == 13 {
                // LF or CR
                let content = string(from: Array(scalars[lineStart..<i]))
                lines.append((content, String(scalars[i])))
                i += 1
                lineStart = i
            } else {
                i += 1
            }
        }

        // Last segment (no trailing break)
        if lineStart <= scalars.count {
            let content = string(from: Array(scalars[lineStart..<scalars.count]))
            lines.append((content, ""))
        }

        return lines
    }

    // MARK: - Word splitting

    /// Splits a line into words using the camelCase-aware word splitting rules.
    static func splitWords(_ line: String) -> [String] {
        let scalars = Array(line.unicodeScalars)
        guard !scalars.isEmpty else { return [] }

        var words: [String] = []
        var wordScalars: [Unicode.Scalar] = []

        var i = 0
        while i < scalars.count {
            let s = scalars[i]

            if !isLetterOrNumber(s) {
                // Separator: flush current word
                if !wordScalars.isEmpty {
                    words.append(string(from: wordScalars))
                    wordScalars.removeAll()
                }
                i += 1
                continue
            }

            // We're in an alphanumeric run. Check for camelCase split points.
            if !wordScalars.isEmpty {
                let prev = wordScalars.last!
                let prevIsLower = isLower(prev)
                let prevIsUpper = isUpper(prev)
                let prevIsDigit = prev.properties.numericType != nil
                let curIsUpper = isUpper(s)

                var shouldSplit = false

                if prevIsDigit || prevIsLower {
                    // Split between lowercase/digit and uppercase: userName -> user, Name
                    // version2Beta -> version2, Beta
                    if curIsUpper {
                        shouldSplit = true
                    }
                }

                if prevIsUpper && curIsUpper {
                    // Split between uppercase and uppercase followed by lowercase:
                    // XMLHttpRequest -> XML, Http, Request
                    // HTTPServer -> HTTP, Server
                    if i + 1 < scalars.count, isLower(scalars[i + 1]) {
                        shouldSplit = true
                    }
                }

                if shouldSplit {
                    words.append(string(from: wordScalars))
                    wordScalars.removeAll()
                }
            }

            wordScalars.append(s)
            i += 1
        }

        if !wordScalars.isEmpty {
            words.append(string(from: wordScalars))
        }

        return words
    }

    // MARK: - Capitalization helpers

    /// Capitalize: first character uppercased, rest lowercased.
    static func capitalize(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars)
        guard !scalars.isEmpty else { return word }

        var result: [Unicode.Scalar] = []
        // Uppercase the first scalar
        let upperFirst = scalars[0].properties.uppercaseMapping
        result.append(contentsOf: upperFirst.unicodeScalars)
        // Lowercase the rest
        for s in scalars.dropFirst() {
            let lower = s.properties.lowercaseMapping
            result.append(contentsOf: lower.unicodeScalars)
        }
        return string(from: result)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    private static func isProseWordContent(_ scalar: Unicode.Scalar) -> Bool {
        if isLetter(scalar) { return true }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return scalar.properties.numericType == .decimal || scalar.properties.numericType == .digit
        }
    }

    private static func isIdentifierLine(_ scalars: [Unicode.Scalar]) -> Bool {
        var hasBoundary = false
        for (index, scalar) in scalars.enumerated() {
            if scalar == "_" || scalar == "-" {
                hasBoundary = true
                continue
            }
            guard !scalar.properties.isWhitespace, isProseWordContent(scalar) else { return false }
            if index > 0, isLower(scalars[index - 1]), isUpper(scalar) {
                hasBoundary = true
            }
        }
        return hasBoundary
    }

    private static func isProseWordScalar(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let scalar = scalars[index]
        if isProseWordContent(scalar) { return true }
        guard scalar == "'" || scalar == "’", index > 0, index + 1 < scalars.count else {
            return false
        }
        return isLetter(scalars[index - 1]) && isLetter(scalars[index + 1])
    }

    private static func startsSentence(_ scalars: [Unicode.Scalar], after index: Int) -> Bool {
        guard scalars[index] == "." || scalars[index] == "!" || scalars[index] == "?" else {
            return false
        }
        var next = index + 1
        while next < scalars.count, ["'", "\"", "’", "”", ")", "]"].contains(scalars[next]) {
            next += 1
        }
        return next < scalars.count && scalars[next].properties.isWhitespace
    }

    private static func convertProseWord(
        _ word: [Unicode.Scalar], style: Style, sentenceStart: Bool, lineHasLowercase: Bool
    ) -> String {
        let letters = word.filter { isLetter($0) }
        guard !letters.isEmpty else { return string(from: word) }

        // All-caps prose is normalized; acronyms in mixed-case prose are preserved.
        let allUppercase = letters.allSatisfy { isUpper($0) }
        let preserve = allUppercase
            ? letters.count >= 2 && lineHasLowercase
            : letters.dropFirst().contains { isUpper($0) }
        if preserve { return string(from: word) }

        let uppercaseFirst = style == .title || sentenceStart || isPronounI(word)
        var result = ""
        var isFirstLetter = true
        for scalar in word {
            guard isLetter(scalar) else {
                result.unicodeScalars.append(scalar)
                continue
            }
            result += uppercaseFirst && isFirstLetter
                ? scalar.properties.uppercaseMapping
                : scalar.properties.lowercaseMapping
            isFirstLetter = false
        }
        return result
    }

    /// "I" and its contractions ("I'm", "I’ll") stay capitalized in Sentence case.
    private static func isPronounI(_ word: [Unicode.Scalar]) -> Bool {
        guard let first = word.first, first == "i" || first == "I" else { return false }
        return word.count == 1 || word[1] == "'" || word[1] == "’"
    }

    private static func convertProse(_ scalars: [Unicode.Scalar], style: Style) -> String {
        let lineHasLowercase = scalars.contains { isLower($0) }
        var result = ""
        var index = 0
        var sentenceStart = true

        while index < scalars.count {
            guard isProseWordScalar(scalars, at: index) else {
                if startsSentence(scalars, after: index) { sentenceStart = true }
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }

            let start = index
            repeat { index += 1 } while index < scalars.count && isProseWordScalar(scalars, at: index)
            let word = Array(scalars[start..<index])
            result += convertProseWord(
                word, style: style, sentenceStart: sentenceStart, lineHasLowercase: lineHasLowercase
            )
            if word.contains(where: { isLetter($0) }) { sentenceStart = false }
        }
        return result
    }

    // MARK: - Style converters (split-based)

    static func convertSplit(_ text: String, style: Style, cancellation: CancellationCheck) -> String? {
        let lines = splitLines(text)
        var output: [UInt8] = []
        var lineIndex = 0

        for (content, lineBreak) in lines {
            // Check cancellation every few lines
            lineIndex += 1
            if lineIndex % 1000 == 0, cancellation.isCancelled {
                return nil
            }

            if content.isEmpty {
                // Empty line: just append the break
                if !lineBreak.isEmpty {
                    output.append(contentsOf: lineBreak.utf8)
                }
                continue
            }

            if style == .title || style == .sentence {
                let scalars = Array(content.unicodeScalars)
                if !isIdentifierLine(scalars) {
                    output.append(contentsOf: convertProse(scalars, style: style).utf8)
                    output.append(contentsOf: lineBreak.utf8)
                    continue
                }
            }

            let words = splitWords(content)
            let converted: String

            switch style {
            case .camel:
                if words.isEmpty {
                    converted = ""
                } else {
                    var parts: [String] = []
                    parts.append(words[0].lowercased())
                    for w in words.dropFirst() {
                        parts.append(capitalize(w))
                    }
                    converted = parts.joined()
                }

            case .pascal:
                converted = words.map { capitalize($0) }.joined()

            case .snake:
                converted = words.map { $0.lowercased() }.joined(separator: "_")

            case .kebab:
                converted = words.map { $0.lowercased() }.joined(separator: "-")

            case .constant:
                converted = words.map { $0.uppercased() }.joined(separator: "_")

            case .title:
                converted = words.map { capitalize($0) }.joined(separator: " ")

            case .sentence:
                if words.isEmpty {
                    converted = ""
                } else {
                    var parts: [String] = []
                    parts.append(capitalize(words[0]))
                    for w in words.dropFirst() {
                        parts.append(w.lowercased())
                    }
                    converted = parts.joined(separator: " ")
                }

            default:
                converted = content
            }

            output.append(contentsOf: converted.utf8)
            output.append(contentsOf: lineBreak.utf8)
        }

        return String(bytes: output, encoding: .utf8) ?? text
    }

    // MARK: - Lower / Upper (no splitting)

    static func convertLower(_ text: String, cancellation: CancellationCheck) -> String? {
        let lines = splitLines(text)
        var output: [UInt8] = []
        var lineIndex = 0

        for (content, lineBreak) in lines {
            lineIndex += 1
            if lineIndex % 1000 == 0, cancellation.isCancelled {
                return nil
            }
            output.append(contentsOf: content.lowercased().utf8)
            output.append(contentsOf: lineBreak.utf8)
        }

        return String(bytes: output, encoding: .utf8) ?? text
    }

    static func convertUpper(_ text: String, cancellation: CancellationCheck) -> String? {
        let lines = splitLines(text)
        var output: [UInt8] = []
        var lineIndex = 0

        for (content, lineBreak) in lines {
            lineIndex += 1
            if lineIndex % 1000 == 0, cancellation.isCancelled {
                return nil
            }
            output.append(contentsOf: content.uppercased().utf8)
            output.append(contentsOf: lineBreak.utf8)
        }

        return String(bytes: output, encoding: .utf8) ?? text
    }

    // MARK: - Slug

    static func convertSlug(_ text: String, cancellation: CancellationCheck) -> String? {
        let lines = splitLines(text)
        var output: [UInt8] = []
        var lineIndex = 0

        for (content, lineBreak) in lines {
            lineIndex += 1
            if lineIndex % 1000 == 0, cancellation.isCancelled {
                return nil
            }

            if content.isEmpty {
                if !lineBreak.isEmpty {
                    output.append(contentsOf: lineBreak.utf8)
                }
                continue
            }

            // Transliterate to ASCII
            let transliterated = (content.applyingTransform(
                StringTransform("Any-Latin; Latin-ASCII"),
                reverse: false
            ) ?? content).lowercased()

            // Split into words of ASCII letters and digits only
            let scalars = Array(transliterated.unicodeScalars)
            var words: [String] = []
            var wordScalars: [Unicode.Scalar] = []

            for s in scalars {
                let isAsciiAlphaOrDigit = (s.value >= 97 && s.value <= 122) || (s.value >= 48 && s.value <= 57)
                if isAsciiAlphaOrDigit {
                    wordScalars.append(s)
                } else {
                    if !wordScalars.isEmpty {
                        words.append(string(from: wordScalars))
                        wordScalars.removeAll()
                    }
                }
            }
            if !wordScalars.isEmpty {
                words.append(string(from: wordScalars))
            }

            let slug = words.joined(separator: "-")
            output.append(contentsOf: slug.utf8)
            output.append(contentsOf: lineBreak.utf8)
        }

        return String(bytes: output, encoding: .utf8) ?? text
    }
}
