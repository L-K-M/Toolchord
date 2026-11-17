import AppKit
import ToolchordCore

/// Colors JSON and XML text lexically. Highlighting is cosmetic: it never
/// changes the text, tolerates malformed input, and is skipped above
/// ``maxHighlightedLength`` to keep large results responsive.
@MainActor
enum SyntaxHighlighter {
    static let maxHighlightedLength = 256 * 1024

    static func attributedString(for text: String, syntax: SyntaxKind, style: PaletteStyle = .standard) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.codeLineHeight
        let base: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.nsColor(.code),
            .paragraphStyle: paragraph,
        ]
        let result = NSMutableAttributedString(string: text, attributes: base)
        guard text.utf16.count <= maxHighlightedLength else { return result }
        let units = Array(text.utf16)
        let colors = TokenColors(style: style)
        switch syntax {
        case .plain: break
        case .json: highlightJSON(units, colors: colors, into: result)
        case .xml: highlightXML(units, colors: colors, into: result)
        }
        return result
    }

    /// One highlight's token colors, made once rather than per token.
    private struct TokenColors {
        let key: NSColor
        let string: NSColor
        let number: NSColor
        let literal: NSColor
        let punctuation: NSColor
        let comment: NSColor

        init(style: PaletteStyle) {
            key = style.nsColor(.keys)
            string = style.nsColor(.strings)
            number = style.nsColor(.numbers)
            literal = style.nsColor(.literals)
            punctuation = style.nsColor(.punctuation)
            comment = style.nsColor(.comments)
        }
    }

    // MARK: - JSON

    private static func highlightJSON(_ units: [UInt16], colors: TokenColors, into result: NSMutableAttributedString) {
        var index = 0
        func color(_ range: Range<Int>, _ color: NSColor) {
            result.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.lowerBound, length: range.count))
        }
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 0x22: // "
                let start = index
                index += 1
                while index < units.count, units[index] != 0x22 {
                    index += units[index] == 0x5C ? 2 : 1
                }
                index = min(index + 1, units.count)
                var lookahead = index
                while lookahead < units.count, [0x20, 0x09, 0x0A, 0x0D].contains(units[lookahead]) { lookahead += 1 }
                let isKey = lookahead < units.count && units[lookahead] == 0x3A
                color(start..<index, isKey ? colors.key : colors.string)
            case 0x2D, 0x30...0x39: // - or digit
                let start = index
                while index < units.count, isNumberUnit(units[index]) { index += 1 }
                color(start..<index, colors.number)
            case 0x74, 0x66, 0x6E: // t f n
                let start = index
                while index < units.count, (0x61...0x7A).contains(units[index]) { index += 1 }
                color(start..<index, colors.literal)
            case 0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C:
                color(index..<(index + 1), colors.punctuation)
                index += 1
            default:
                index += 1
            }
        }
    }

    private static func isNumberUnit(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || unit == 0x2D || unit == 0x2B || unit == 0x2E || unit == 0x65 || unit == 0x45
    }

    // MARK: - XML

    private static func highlightXML(_ units: [UInt16], colors: TokenColors, into result: NSMutableAttributedString) {
        func color(_ range: Range<Int>, _ color: NSColor) {
            guard !range.isEmpty else { return }
            result.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.lowerBound, length: range.count))
        }
        func starts(_ prefix: String, at index: Int) -> Bool {
            let prefixUnits = Array(prefix.utf16)
            guard index + prefixUnits.count <= units.count else { return false }
            return Array(units[index..<(index + prefixUnits.count)]) == prefixUnits
        }
        func find(_ terminator: String, from index: Int) -> Int {
            let terminatorUnits = Array(terminator.utf16)
            var position = index
            while position + terminatorUnits.count <= units.count {
                if units[position] == terminatorUnits[0], Array(units[position..<(position + terminatorUnits.count)]) == terminatorUnits {
                    return position + terminatorUnits.count
                }
                position += 1
            }
            return units.count
        }

        var index = 0
        while index < units.count {
            guard units[index] == 0x3C else { // <
                index += 1
                continue
            }
            if starts("<!--", at: index) {
                let end = find("-->", from: index + 4)
                color(index..<end, colors.comment)
                index = end
            } else if starts("<![CDATA[", at: index) {
                let end = find("]]>", from: index + 9)
                color(index..<end, colors.literal)
                index = end
            } else if starts("<?", at: index) || starts("<!", at: index) {
                let end = find(">", from: index + 2)
                color(index..<end, colors.literal)
                index = end
            } else {
                // Tag: punctuation, name, then attributes.
                let start = index
                index += 1
                if index < units.count, units[index] == 0x2F { index += 1 }
                color(start..<index, colors.punctuation)
                let nameStart = index
                while index < units.count, !isXMLBreak(units[index]) { index += 1 }
                color(nameStart..<index, colors.key)
                while index < units.count, units[index] != 0x3E {
                    let unit = units[index]
                    if unit == 0x22 || unit == 0x27 {
                        let quote = unit
                        let valueStart = index
                        index += 1
                        while index < units.count, units[index] != quote { index += 1 }
                        index = min(index + 1, units.count)
                        color(valueStart..<index, colors.string)
                    } else if !isXMLBreak(unit) {
                        let attributeStart = index
                        while index < units.count, !isXMLBreak(units[index]) { index += 1 }
                        color(attributeStart..<index, colors.number)
                    } else {
                        if unit == 0x2F || unit == 0x3D { color(index..<(index + 1), colors.punctuation) }
                        index += 1
                    }
                }
                if index < units.count {
                    color(index..<(index + 1), colors.punctuation)
                    index += 1
                }
            }
        }
    }

    private static func isXMLBreak(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x3E || unit == 0x2F || unit == 0x3D || unit == 0x22 || unit == 0x27
    }
}
