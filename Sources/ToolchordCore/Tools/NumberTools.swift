import Foundation

/// Number base conversion: decimal, hex, binary, octal with arbitrary precision.
public enum NumberTools {

    private static let maxDigits = 4096

    public static let commands: [ToolCommand] = [
        decimalCommand,
        hexCommand,
        binaryCommand,
        octalCommand,
    ]

    private static let fromOption = ToolOption.choice(
        "from",
        "Read as",
        [
            ToolOption.Choice("auto", "Auto"),
            ToolOption.Choice("10", "Decimal"),
            ToolOption.Choice("16", "Hex"),
            ToolOption.Choice("2", "Binary"),
            ToolOption.Choice("8", "Octal"),
        ],
        default: "auto"
    )

    private static let prefixOption = ToolOption.toggle("prefix", "Add prefix", default: false)

    // MARK: - Commands

    private static let decimalCommand = makeCommand(
        id: "number.decimal",
        title: "Convert to Decimal",
        summary: "Base 10 from hex, binary, or octal",
        aliases: ["to decimal", "hex to decimal", "binary to decimal", "octal to decimal", "base 10"],
        copyNoun: "decimal",
        targetBase: 10,
        affinity: { profile in profile.has(.hex) ? 70 : 0 }
    )

    private static let hexCommand = makeCommand(
        id: "number.hex",
        title: "Convert to Hex",
        summary: "Base 16",
        aliases: ["to hex", "decimal to hex", "hexadecimal", "base 16"],
        copyNoun: "hex",
        targetBase: 16,
        affinity: { profile in profile.has(.number) ? 60 : 0 }
    )

    private static let binaryCommand = makeCommand(
        id: "number.binary",
        title: "Convert to Binary",
        summary: "Base 2",
        aliases: ["to binary", "decimal to binary", "base 2"],
        copyNoun: "binary",
        targetBase: 2,
        affinity: { profile in profile.has(.number) ? 55 : 0 }
    )

    private static let octalCommand = makeCommand(
        id: "number.octal",
        title: "Convert to Octal",
        summary: "Base 8",
        aliases: ["to octal", "decimal to octal", "base 8"],
        copyNoun: "octal",
        targetBase: 8,
        affinity: { profile in profile.has(.number) ? 35 : 0 }
    )

    private static func makeCommand(
        id: String,
        title: String,
        summary: String,
        aliases: [String],
        copyNoun: String,
        targetBase: Int,
        affinity: @escaping @Sendable (InputProfile) -> Int
    ) -> ToolCommand {
        ToolCommand(
            id: id,
            title: title,
            summary: summary,
            group: .number,
            icon: .symbol("number"),
            aliases: aliases,
            options: [fromOption, prefixOption],
            copyNoun: copyNoun,
            affinity: affinity,
            evaluate: { request in evaluate(request, targetBase: targetBase) }
        )
    }

    // MARK: - Evaluation

    static func evaluate(_ request: ToolRequest, targetBase: Int) -> ToolResult {
        let text = request.input.text ?? ""
        let fromChoice = request.options.choice("from", default: "auto")
        let addPrefix = request.options.flag("prefix", default: false)

        let explicitBase: Int?
        switch fromChoice {
        case "10": explicitBase = 10
        case "16": explicitBase = 16
        case "2":  explicitBase = 2
        case "8":  explicitBase = 8
        default:   explicitBase = nil
        }

        let parsed = parseNumber(text, explicitBase: explicitBase)
        switch parsed {
        case .empty:
            return .invalid(ToolDiagnostic("Enter a number."))
        case .prefixNoDigits(let prefixStr, let location):
            return .invalid(ToolDiagnostic("Expected digits after “\(prefixStr)”.", at: location))
        case .badDigit(let ch, let base, let location):
            let msg: String
            switch base {
            case 16: msg = "“\(ch)” isn’t a hex digit."
            case 2:  msg = "“\(ch)” isn’t a binary digit."
            case 8:  msg = "“\(ch)” isn’t an octal digit."
            default: msg = "“\(ch)” isn’t a decimal digit."
            }
            return .invalid(ToolDiagnostic(msg, at: location))
        case .wrongPrefix(let prefixStr, let baseName):
            return .invalid(ToolDiagnostic("“\(prefixStr)” doesn’t match Read as \(baseName)."))
        case .tooManyDigits:
            return .tooLarge("Numbers can have at most 4,096 digits.")
        case .success(let sign, let digits, let detectedBase):
            let bigNum = BigInt(fromDigits: digits, base: detectedBase)
            let addPfx = addPrefix && targetBase != 10

            // Never output -0.
            let isZero = bigNum.limbs == [0]
            let effectiveSign = sign && !isZero

            let primary = formatNumber(bigNum, base: targetBase, sign: effectiveSign, prefix: addPfx)

            let fields: [ResultField] = [
                ResultField(id: "decimal", label: "Decimal",
                    value: formatNumber(bigNum, base: 10, sign: effectiveSign, prefix: false)),
                ResultField(id: "hex", label: "Hex",
                    value: formatNumber(bigNum, base: 16, sign: effectiveSign, prefix: addPfx)),
                ResultField(id: "binary", label: "Binary",
                    value: formatNumber(bigNum, base: 2, sign: effectiveSign, prefix: addPfx)),
                ResultField(id: "octal", label: "Octal",
                    value: formatNumber(bigNum, base: 8, sign: effectiveSign, prefix: addPfx)),
            ]

            let status = "Read as \(baseName(from: detectedBase))"

            return .success(ToolOutput(
                primaryText: primary,
                status: status,
                fields: fields
            ))
        }
    }

    // MARK: - Parsing

    private enum ParseResult {
        case empty
        case prefixNoDigits(String, TextLocation)
        case badDigit(Character, Int, TextLocation)
        case wrongPrefix(String, String)
        case tooManyDigits
        case success(sign: Bool, digits: [Int], detectedBase: Int)
    }

    private static func baseName(from base: Int) -> String {
        switch base {
        case 16: return "hex"
        case 2:  return "binary"
        case 8:  return "octal"
        default: return "decimal"
        }
    }

    private static func parseNumber(_ text: String, explicitBase: Int?) -> ParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // Diagnostics point into the original input, past any leading whitespace.
        let leading = text.unicodeScalars.prefix { CharacterSet.whitespacesAndNewlines.contains($0) }.count

        let scalars = Array(trimmed.unicodeScalars)
        var i = 0

        var negative = false
        if i < scalars.count, scalars[i] == "-" {
            negative = true
            i += 1
        }
        guard i < scalars.count else { return .empty }

        var detectedPrefix: String? = nil
        var prefixBase: Int? = nil
        if i + 1 < scalars.count, scalars[i] == "0" {
            let second = scalars[i + 1]
            if second == "x" || second == "X" {
                detectedPrefix = "0x"; prefixBase = 16; i += 2
            } else if (second == "b" || second == "B") && explicitBase != 16 {
                // With Read as Hex, "0B…" is two hex digits, not a binary prefix.
                detectedPrefix = "0b"; prefixBase = 2; i += 2
            } else if second == "o" || second == "O" {
                detectedPrefix = "0o"; prefixBase = 8; i += 2
            }
        }

        let readBase: Int
        if let explicit = explicitBase {
            if let pBase = prefixBase, pBase != explicit {
                let baseName: String
                switch explicit {
                case 16: baseName = "Hex"
                case 2:  baseName = "Binary"
                case 8:  baseName = "Octal"
                default: baseName = "Decimal"
                }
                return .wrongPrefix(detectedPrefix!, baseName)
            }
            readBase = explicit
        } else if let pBase = prefixBase {
            readBase = pBase
        } else {
            var hasHexDigit = false
            var j = i
            while j < scalars.count {
                let v = scalars[j].value
                if (0x61...0x66).contains(v) || (0x41...0x46).contains(v) {
                    hasHexDigit = true; break
                }
                j += 1
            }
            readBase = hasHexDigit ? 16 : 10
        }

        var digits: [Int] = []
        var lastWasDigit = false
        var scalarIdx = i

        while i < scalars.count {
            let s = scalars[i]
            let v = s.value

            if v == 0x5F {
                if !lastWasDigit {
                    let loc = TextLocator.location(ofScalarOffset: leading + scalarIdx, in: text)
                    return .badDigit(Character(s), readBase, loc)
                }
                lastWasDigit = false
                i += 1; scalarIdx += 1; continue
            }

            let digitValue: Int
            if v >= 0x30, v <= 0x39 {
                digitValue = Int(v - 0x30)
            } else if v >= 0x61, v <= 0x66 {
                digitValue = Int(v - 0x61) + 10
            } else if v >= 0x41, v <= 0x46 {
                digitValue = Int(v - 0x41) + 10
            } else {
                let loc = TextLocator.location(ofScalarOffset: leading + scalarIdx, in: text)
                return .badDigit(Character(s), readBase, loc)
            }

            if digitValue >= readBase {
                let loc = TextLocator.location(ofScalarOffset: leading + scalarIdx, in: text)
                return .badDigit(Character(s), readBase, loc)
            }

            digits.append(digitValue)
            lastWasDigit = true
            i += 1; scalarIdx += 1
        }

        if digits.isEmpty {
            if let prefix = detectedPrefix {
                let loc = TextLocator.location(ofScalarOffset: leading + i, in: text)
                return .prefixNoDigits(prefix, loc)
            }
            return .empty
        }

        if !lastWasDigit {
            let loc = TextLocator.location(ofScalarOffset: leading + scalarIdx - 1, in: text)
            return .badDigit("_", readBase, loc)
        }

        if digits.count > maxDigits {
            return .tooManyDigits
        }

        // Strip leading zeros.
        var start = 0
        while start < digits.count - 1, digits[start] == 0 {
            start += 1
        }
        let significant = Array(digits[start...])

        return .success(sign: negative, digits: significant, detectedBase: readBase)
    }

    // MARK: - BigInt

    /// Non-negative big integer using base 10^9 limbs (least significant first).
    private struct BigInt {
        var limbs: [UInt64]
        private static let base: UInt64 = 1_000_000_000

        init(zero: Bool = false) {
            limbs = [0]
        }

        /// Build from digits in the given base (most significant first).
        init(fromDigits digits: [Int], base: Int) {
            if digits.isEmpty || (digits.count == 1 && digits[0] == 0) {
                limbs = [0]
                return
            }
            limbs = [0]
            let b = UInt64(base)
            for d in digits {
                multiplyBy(b)
                addLow(UInt64(d))
            }
        }

        /// Multiply the number by a small base.
        private mutating func multiplyBy(_ multiplier: UInt64) {
            var carry: UInt64 = 0
            for idx in limbs.indices {
                let product = limbs[idx] * multiplier + carry
                limbs[idx] = product % BigInt.base
                carry = product / BigInt.base
            }
            while carry > 0 {
                limbs.append(carry % BigInt.base)
                carry /= BigInt.base
            }
        }

        /// Add a small value to the least significant limb, propagating carry.
        private mutating func addLow(_ value: UInt64) {
            if limbs.isEmpty { limbs.append(0) }
            limbs[0] += value
            var idx = 0
            while idx < limbs.count, limbs[idx] >= BigInt.base {
                limbs[idx] -= BigInt.base
                if idx + 1 < limbs.count {
                    limbs[idx + 1] += 1
                } else {
                    limbs.append(1)
                }
                idx += 1
            }
        }

        /// Repeated division by a small base, returning digits (least significant first).
        func toDigits(base: Int) -> [Int] {
            if limbs == [0] { return [0] }

            let b = UInt64(base)
            var remaining = self.limbs
            var digits: [Int] = []

            while !remaining.allSatisfy({ $0 == 0 }) {
                var carry: UInt64 = 0
                for idx in (0..<remaining.count).reversed() {
                    let total = remaining[idx] + carry
                    remaining[idx] = total / b
                    carry = (total % b) * BigInt.base
                }
                // After processing limb 0, carry = (digit * BigInt.base).
                // The digit is carry / BigInt.base, but carry could overflow.
                // Actually: after limb 0, carry = (remaining[0]_old % b) * BigInt.base.
                // But we already updated remaining[0]. The digit is the remainder of
                // the full number divided by b. We need to extract it from carry.
                // carry = digit * BigInt.base, so digit = carry / BigInt.base.
                // But carry could be >= BigInt.base if digit >= base... no, digit < base.
                // carry = (total_0 % b) * BigInt.base where total_0 = remaining[0]_old + carry_from_1.
                // total_0 % b < b, so carry < b * BigInt.base.
                // digit = carry / BigInt.base. Since carry = digit * BigInt.base, this works.
                // But wait — carry from limb 1 is (remaining[1]_old % b) * BigInt.base,
                // which could be up to (b-1) * BigInt.base. Then total_0 = remaining[0]_old + carry.
                // remaining[0]_old < BigInt.base, carry < b * BigInt.base.
                // total_0 < BigInt.base + b * BigInt.base = (b+1) * BigInt.base.
                // total_0 / b < (b+1)/b * BigInt.base ≈ BigInt.base. OK, fits in UInt64.
                // total_0 % b < b. carry_out = (total_0 % b) * BigInt.base < b * BigInt.base.
                // For b=16, carry < 16 * 10^9 ≈ 1.6 * 10^10, fits in UInt64 (max ~1.8 * 10^19).
                // digit = carry / BigInt.base. Correct.
                let digit = Int(carry / BigInt.base)
                digits.append(digit)
            }

            return digits.reversed()
        }
    }

    // MARK: - Formatting

    private static func formatNumber(_ num: BigInt, base: Int, sign: Bool, prefix: Bool) -> String {
        let digits = num.toDigits(base: base)
        let hexChars = Array("0123456789abcdef")

        var bytes: [UInt8] = []
        if sign { bytes.append(0x2D) }
        if prefix {
            switch base {
            case 16: bytes.append(contentsOf: "0x".utf8)
            case 2:  bytes.append(contentsOf: "0b".utf8)
            case 8:  bytes.append(contentsOf: "0o".utf8)
            default: break
            }
        }
        for d in digits {
            let ch = hexChars[d]
            bytes.append(UInt8(ch.utf8.first!))
        }
        return String(bytes: bytes, encoding: .utf8)!
    }
}
