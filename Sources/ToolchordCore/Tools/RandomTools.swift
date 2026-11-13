import CryptoKit
import Foundation

/// Random strings and lorem ipsum. Randomness is drawn once in `makeSeed`;
/// evaluation maps the seed deterministically, so option changes re-map the
/// same seed and the value on screen stays stable until Regenerate.
public enum RandomTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "random.string",
            title: "Generate Random String",
            summary: "Secure random characters",
            group: .random,
            icon: .symbol("dice"),
            aliases: ["random string", "password", "token", "secret", "api key", "random password", "random token"],
            input: .none,
            options: [
                .choice("length", "Length", ["16", "24", "32", "64"].map { ToolOption.Choice($0, $0) }, default: "32"),
                .choice("characters", "Characters", [
                    .init("alnum", "Letters & digits"),
                    .init("symbols", "With symbols"),
                    .init("hex", "Hex"),
                ], default: "alnum"),
            ],
            copyNoun: "string",
            makeSeed: { _ in
                var generator = SystemRandomNumberGenerator()
                return (0..<seedByteCount).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
            },
            regenerateTitle: "Regenerate String",
            evaluate: evaluateString
        ),
        ToolCommand(
            id: "random.lorem",
            title: "Generate Lorem Ipsum",
            summary: "Placeholder text",
            group: .random,
            icon: .symbol("text.alignleft"),
            aliases: ["lorem", "lorem ipsum", "placeholder text", "dummy text", "filler text"],
            input: .none,
            options: [
                .choice("length", "Length", [
                    .init("sentence", "Sentence"),
                    .init("paragraph", "Paragraph"),
                    .init("three", "3 paragraphs"),
                    .init("five", "5 paragraphs"),
                ], default: "paragraph"),
            ],
            copyNoun: "text",
            makeSeed: { _ in String(UInt64.random(in: .min ... .max)) },
            regenerateTitle: "Regenerate Text",
            evaluate: evaluateLorem
        ),
    ]

    static let seedByteCount = 512
    static let missingSeed = ToolResult.needsInput("Select this command again to generate a value.")

    // MARK: - Random string

    static let alphanumerics = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".unicodeScalars)
    static let symbols = alphanumerics + Array("!#$%&()*+,-./:;<=>?@[]^_{|}~".unicodeScalars)
    static let hexDigits = Array("0123456789abcdef".unicodeScalars)

    static func evaluateString(_ request: ToolRequest) -> ToolResult {
        guard let seed = request.seed, let bytes = decodeHex(seed), bytes.count == seedByteCount else { return missingSeed }
        let length = Int(request.options.choice("length", default: "32")) ?? 32
        let characters = request.options.choice("characters", default: "alnum")
        let alphabet: [Unicode.Scalar]
        switch characters {
        case "symbols": alphabet = symbols
        case "hex": alphabet = hexDigits
        default: alphabet = alphanumerics
        }
        let stream = derivedBytes(seed: bytes, length: length, characters: characters)
        guard let text = map(stream, to: alphabet, length: length) else { return missingSeed }
        let entropy = Int((Double(length) * log2(Double(alphabet.count))).rounded(.down))
        return .success(ToolOutput(
            primaryText: text,
            status: "\(length) characters",
            fields: [ResultField(id: "entropy", label: "Entropy", value: "\(entropy) bits", isCopyable: false, isMonospaced: false)],
            // Used as passwords, tokens, and API keys (see the aliases).
            sensitivity: .secret
        ))
    }

    /// An independent byte stream for one combination of options, derived
    /// from the secret seed with HKDF-SHA256. The value stays stable while it
    /// is on screen, but a value shown for one length or alphabet reveals
    /// nothing about the value for another (a 16-character string is not the
    /// prefix of the 64-character one).
    static func derivedBytes(seed: [UInt8], length: Int, characters: String) -> [UInt8] {
        let info = Data("toolchord.random.string;length=\(length);characters=\(characters)".utf8)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: seed), info: info, outputByteCount: seedByteCount)
        return key.withUnsafeBytes { Array($0) }
    }

    /// Unbiased mapping by rejection: bytes at or above the largest multiple
    /// of the alphabet size are skipped. `nil` if the seed runs out.
    static func map(_ bytes: [UInt8], to alphabet: [Unicode.Scalar], length: Int) -> String? {
        let size = alphabet.count
        let limit = 256 - (256 % size)
        var scalars = String.UnicodeScalarView()
        for byte in bytes where Int(byte) < limit {
            scalars.append(alphabet[Int(byte) % size])
            if scalars.count == length { return String(scalars) }
        }
        return nil
    }

    static func decodeHex(_ text: String) -> [UInt8]? {
        let digits = Array(text.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = hexValue(digits[index]), let low = hexValue(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - 48
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - 87
        default: nil
        }
    }

    // MARK: - Lorem ipsum

    static let firstSentence = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

    static let vocabulary = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
        "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim",
        "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip",
        "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
        "velit", "esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat",
        "non", "proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit", "anim", "id",
        "est", "laborum", "praesent", "vitae", "semper", "porta", "mauris", "viverra", "facilisis", "integer",
    ]

    /// SplitMix64: a small, well-distributed generator, deterministic per seed.
    struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func next(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
    }

    static func evaluateLorem(_ request: ToolRequest) -> ToolResult {
        guard let seedText = request.seed, let seed = UInt64(seedText) else { return missingSeed }
        let paragraphs: Int
        switch request.options.choice("length", default: "paragraph") {
        case "sentence": paragraphs = 0
        case "three": paragraphs = 3
        case "five": paragraphs = 5
        default: paragraphs = 1
        }
        let text = paragraphs == 0 ? firstSentence : lorem(paragraphs: paragraphs, seed: seed)
        let words = text.split(separator: " ").count
        return .success(ToolOutput(primaryText: text, status: words == 1 ? "1 word" : "\(words) words"))
    }

    static func lorem(paragraphs: Int, seed: UInt64) -> String {
        var generator = SplitMix64(state: seed)
        var result: [String] = []
        for paragraph in 0..<paragraphs {
            let count = generator.next(in: 4...7)
            var sentences: [String] = paragraph == 0 ? [firstSentence] : []
            while sentences.count < count {
                sentences.append(sentence(using: &generator))
            }
            result.append(sentences.joined(separator: " "))
        }
        return result.joined(separator: "\n\n")
    }

    static func sentence(using generator: inout SplitMix64) -> String {
        let count = generator.next(in: 6...14)
        var words = (0..<count).map { _ in vocabulary[generator.next(in: 0...(vocabulary.count - 1))] }
        if count >= 8 && generator.next() % 2 == 0 {
            let commaAfter = generator.next(in: 2...(count - 3))
            words[commaAfter] += ","
        }
        words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        return words.joined(separator: " ") + "."
    }
}
