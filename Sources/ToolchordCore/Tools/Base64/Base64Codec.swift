import Foundation

enum Base64Codec {
    enum Alphabet: Sendable { case standard, url }
    struct Failure: Error, Sendable, Equatable {
        var message: String
        /// UTF-8 byte offset in the original input.
        var offset: Int?
    }
    enum ProcessingError: Error {
        case invalid(Failure), cancelled, tooLarge
    }

    static func encode<Bytes: Collection>(_ bytes: Bytes, alphabet: Alphabet) -> String where Bytes.Element == UInt8 {
        // Unbounded, noncancellable entry point for other tool modules.
        do {
            return try encode(bytes, alphabet: alphabet, maxOutputBytes: Int.max, cancellation: .never)
        } catch {
            preconditionFailure("Unbounded Base64 encoding cannot be cancelled or exceed a limit.")
        }
    }

    static func encode<Bytes: Collection>(
        _ bytes: Bytes, alphabet: Alphabet, maxOutputBytes: Int, cancellation: CancellationCheck
    ) throws -> String where Bytes.Element == UInt8 {
        let table = Array((alphabet == .standard
            ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").utf8)
        let count = bytes.count
        let full = count / 3 * 4
        let remainder = count % 3
        let size = full + (remainder == 0 ? 0 : (alphabet == .standard ? 4 : remainder + 1))
        if cancellation.isCancelled { throw ProcessingError.cancelled }
        guard size <= maxOutputBytes else { throw ProcessingError.tooLarge }
        var output: [UInt8] = []
        output.reserveCapacity(size)
        var iterator = bytes.makeIterator()
        var processed = 0
        while let a = iterator.next() {
            if processed % 3072 == 0, cancellation.isCancelled { throw ProcessingError.cancelled }
            let b = iterator.next()
            let c = iterator.next()
            output.append(table[Int(a >> 2)])
            output.append(table[Int((a & 3) << 4 | (b ?? 0) >> 4)])
            if let b { output.append(table[Int((b & 15) << 2 | (c ?? 0) >> 6)]) }
            else if alphabet == .standard { output.append(61) }
            if let c { output.append(table[Int(c & 63)]) }
            else if alphabet == .standard { output.append(61) }
            processed += 3
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func decode(_ text: String, alphabet: Alphabet, ignoreWhitespace: Bool = false) -> Result<[UInt8], Failure> {
        do {
            return .success(try decode(text, alphabet: alphabet, ignoreWhitespace: ignoreWhitespace,
                                       maxOutputBytes: Int.max, cancellation: .never))
        } catch ProcessingError.invalid(let failure) {
            return .failure(failure)
        } catch {
            preconditionFailure("Unbounded Base64 decoding cannot be cancelled or exceed a limit.")
        }
    }

    static func decode(_ text: String, alphabet: Alphabet, ignoreWhitespace: Bool,
                       maxOutputBytes: Int, cancellation: CancellationCheck) throws -> [UInt8] {
        func fail(_ message: String, _ offset: Int) throws -> Never {
            throw ProcessingError.invalid(Failure(message: message, offset: offset))
        }
        // Whitespace around the encoding is never part of it: a token copied
        // from a terminal or an editor usually ends with a line break. Only
        // whitespace inside the encoding needs Ignore whitespace.
        let content = contentBounds(of: text)
        var values: [UInt8] = []
        values.reserveCapacity(content.count)
        var offset = 0
        var lastDigitOffset = 0
        var firstPadding: Int?
        var padding = 0
        var nextCheck = 0
        for scalar in text.unicodeScalars {
            if offset >= nextCheck {
                if cancellation.isCancelled { throw ProcessingError.cancelled }
                nextCheck = offset + 4096
            }
            defer { offset += scalar.utf8.count }
            guard content.contains(offset) else { continue }
            let n = scalar.value
            if n == 32 || n == 9 || n == 10 || n == 13 {
                if ignoreWhitespace { continue }
                try fail("Base64 contains whitespace. Turn on Ignore whitespace to decode wrapped text.", offset)
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar), !ignoreWhitespace {
                try fail("Base64 contains whitespace. Turn on Ignore whitespace to decode wrapped text.", offset)
            }
            if n == 61 {
                if firstPadding == nil { firstPadding = offset }
                padding += 1
                if padding > 2 { try fail("Too much padding.", offset) }
                continue
            }
            if let firstPadding { try fail("Padding “=” is only allowed at the end.", firstPadding) }
            let value: UInt8
            switch n {
            case 65...90: value = UInt8(n - 65)
            case 97...122: value = UInt8(n - 97 + 26)
            case 48...57: value = UInt8(n - 48 + 52)
            case 43, 47:
                guard alphabet == .standard else {
                    try fail("Contains standard Base64 characters (“+” or “/”). Use Decode Base64.", offset)
                }
                value = n == 43 ? 62 : 63
            case 45, 95:
                guard alphabet == .url else {
                    try fail("Contains URL-safe characters (“-” or “_”). Use Decode Base64URL.", offset)
                }
                value = n == 45 ? 62 : 63
            default: try fail("Invalid Base64 character “\(scalar)”.", offset)
            }
            values.append(value)
            lastDigitOffset = offset
        }
        if cancellation.isCancelled { throw ProcessingError.cancelled }
        let remainder = values.count % 4
        let lengthMessage = "Base64 length is invalid. Check for missing or extra characters."
        if remainder == 1 { try fail(lengthMessage, lastDigitOffset) }
        if padding > 0 {
            guard (remainder == 2 && padding == 2) || (remainder == 3 && padding == 1) else {
                try fail(lengthMessage, firstPadding ?? content.upperBound)
            }
        } else if alphabet == .standard && remainder != 0 {
            try fail("Standard Base64 needs “=” padding. Add padding or use Decode Base64URL.", content.upperBound)
        }
        if let last = values.last, (remainder == 2 && last & 15 != 0) || (remainder == 3 && last & 3 != 0) {
            try fail("The last character has nonzero padding bits, so this isn’t canonical Base64.", lastDigitOffset)
        }
        let size = values.count / 4 * 3 + (remainder == 0 ? 0 : remainder - 1)
        guard size <= maxOutputBytes else { throw ProcessingError.tooLarge }
        var output: [UInt8] = []
        output.reserveCapacity(size)
        var buffer: UInt32 = 0
        var bits = 0
        for (index, value) in values.enumerated() {
            if index % 4096 == 0, cancellation.isCancelled { throw ProcessingError.cancelled }
            buffer = (buffer << 6) | UInt32(value)
            bits += 6
            if bits >= 8 {
                bits -= 8
                output.append(UInt8(truncatingIfNeeded: buffer >> bits))
            }
        }
        return output
    }

    /// UTF-8 offsets of `text` without its leading and trailing whitespace.
    /// Only the whitespace at either end is scanned.
    private static func contentBounds(of text: String) -> Range<Int> {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        while start < scalars.endIndex, CharacterSet.whitespacesAndNewlines.contains(scalars[start]) {
            scalars.formIndex(after: &start)
        }
        var end = scalars.endIndex
        while end > start {
            let previous = scalars.index(before: end)
            guard CharacterSet.whitespacesAndNewlines.contains(scalars[previous]) else { break }
            end = previous
        }
        let lower = text.utf8.distance(from: text.utf8.startIndex, to: start)
        return lower..<(lower + text.utf8.distance(from: start, to: end))
    }
}
