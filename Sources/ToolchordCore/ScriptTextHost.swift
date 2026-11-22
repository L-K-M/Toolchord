import Foundation

/// Platform Unicode services used by scripts. Splitting, transforming,
/// formatting, and command behavior remain in JavaScript.
enum ScriptTextHost {
    static func call(_ name: String, _ args: [Any], _ request: ToolRequest) throws -> Any? {
        switch name {
        case "text.graphemeClasses":
            let value = try text(args, at: 0)
            var classes: [UInt8] = []
            classes.reserveCapacity(value.utf8.count)
            for character in value {
                if classes.count & 0xFFF == 0, request.cancellation.isCancelled { throw CancellationError() }
                // One ASCII marker per extended grapheme: whitespace or other.
                // A compact string avoids bridging a million individual strings.
                classes.append(character.isWhitespace ? 87 : 79)
            }
            return String(decoding: classes, as: UTF8.self)
        case "text.transliterate":
            let value = try text(args, at: 0)
            return value.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? value
        case "text.numericType":
            guard let scalar = try text(args, at: 0).unicodeScalars.first else { return "" }
            switch scalar.properties.numericType {
            case .decimal: return "decimal"
            case .digit: return "digit"
            case .numeric: return "numeric"
            case nil: return ""
            @unknown default: return ""
            }
        case "text.compare":
            let left = try text(args, at: 0)
            let right = try text(args, at: 1)
            guard args.count > 2, let caseSensitive = args[2] as? Bool else {
                throw invalidArguments(name)
            }
            var options: String.CompareOptions = [.numeric]
            if !caseSensitive { options.insert(.caseInsensitive) }
            return left.compare(right, options: options, range: nil, locale: nil).rawValue
        default:
            return nil
        }
    }

    private static func text(_ args: [Any], at index: Int) throws -> String {
        guard args.indices.contains(index), let value = args[index] as? String else {
            throw invalidArguments("text")
        }
        return value
    }

    private static func invalidArguments(_ name: String) -> NSError {
        NSError(domain: "Toolchord.ScriptTextHost", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid arguments for the \(name) Unicode service."
        ])
    }
}
