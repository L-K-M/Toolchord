import Foundation
import Testing
@testable import ToolchordCore

@Suite struct NumberToolsTests {

    // MARK: - Helpers

    private func run(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolOutput {
        let command = try #require(NumberTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func runResult(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolResult {
        let command = try #require(NumberTools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
    }

    private func field(_ output: ToolOutput, id: String) throws -> String {
        try #require(output.fields.first { $0.id == id }?.value)
    }

    // MARK: - Fixtures

    @Test func hex_255() throws {
        let out = try run("number.hex", "255")
        #expect(out.primaryText == "ff")
        #expect(try field(out, id: "decimal") == "255")
        #expect(try field(out, id: "binary") == "11111111")
        #expect(try field(out, id: "octal") == "377")
    }

    @Test func decimal_0xff() throws {
        let out = try run("number.decimal", "0xff")
        #expect(out.primaryText == "255")
    }

    @Test func decimal_ff_autoDetectsHex() throws {
        let out = try run("number.decimal", "ff")
        #expect(out.primaryText == "255")
        #expect(out.status == "Read as hex")
    }

    @Test func hex_negative42() throws {
        let out = try run("number.hex", "-42")
        #expect(out.primaryText == "-2a")
    }

    @Test func decimal_0b1010() throws {
        let out = try run("number.decimal", "0b1010")
        #expect(out.primaryText == "10")
    }

    @Test func hex_withPrefix() throws {
        let out = try run("number.hex", "255", options: ["prefix": "true"])
        #expect(out.primaryText == "0xff")
    }

    @Test func binary_negative5_withPrefix() throws {
        let out = try run("number.binary", "-5", options: ["prefix": "true"])
        #expect(out.primaryText == "-0b101")
    }

    @Test func hex_largeNumber() throws {
        // 2^64 = 18446744073709551616
        let out = try run("number.hex", "18446744073709551616")
        #expect(out.primaryText == "10000000000000000")
    }

    @Test func decimal_largeHex() throws {
        // 0xFFFFFFFFFFFFFFFFFFFFFFFF = 2^96 - 1 (24 hex digits)
        let out = try run("number.decimal", "0xFFFFFFFFFFFFFFFFFFFFFFFF")
        #expect(out.primaryText == "79228162514264337593543950335")
    }

    @Test func decimal_0x_noDigits() throws {
        let result = try runResult("number.decimal", "0x")
        #expect(result.isSuccess == false)
        if case .invalid(let diag) = result {
            #expect(diag.message.contains("Expected digits"))
        } else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func hex_badDigit_12g() throws {
        // "12g" auto-detects as decimal (no a-f), so "g" is a bad decimal digit.
        let result = try runResult("number.hex", "12g")
        if case .invalid(let diag) = result {
            #expect(diag.message == "“g” isn’t a decimal digit.")
            #expect(diag.location?.line == 1)
            #expect(diag.location?.column == 3)
        } else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func decimal_underscore_1_000() throws {
        let out = try run("number.decimal", "1_000")
        #expect(out.primaryText == "1000")
    }

    @Test func decimal_from2_badDigit() throws {
        let result = try runResult("number.decimal", "102", options: ["from": "2"])
        if case .invalid(let diag) = result {
            #expect(diag.message == "“2” isn’t a binary digit.")
            #expect(diag.location?.line == 1)
            #expect(diag.location?.column == 3)
        } else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func decimal_from16_wrongPrefix() throws {
        // With Read as Hex, "0b11" is the hex number 0x0B11; "0o" is still a mismatched prefix.
        #expect(try runResult("number.decimal", "0b11", options: ["from": "16"]).output?.primaryText == "2833")
        let result = try runResult("number.decimal", "0o17", options: ["from": "16"])
        if case .invalid(let diag) = result {
            #expect(diag.message == "“0o” doesn’t match Read as Hex.")
        } else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func hex_zero() throws {
        let out1 = try run("number.hex", "0")
        #expect(out1.primaryText == "0")
        let out2 = try run("number.hex", "-0")
        #expect(out2.primaryText == "0")
    }

    @Test func decimal_emptyInput() throws {
        let result = try runResult("number.decimal", "")
        if case .invalid(let diag) = result {
            #expect(diag.message == "Enter a number.")
        } else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    // MARK: - Additional edge cases

    @Test func decimal_whitespaceOnly() throws {
        let result = try runResult("number.decimal", "   ")
        #expect(result.isSuccess == false)
    }

    @Test func hex_uppercase() throws {
        let out = try run("number.decimal", "0XFF")
        #expect(out.primaryText == "255")
    }

    @Test func binary_simple() throws {
        let out = try run("number.decimal", "0b1010")
        #expect(out.primaryText == "10")
        #expect(out.status == "Read as binary")
    }

    @Test func octal_simple() throws {
        let out = try run("number.decimal", "0o77")
        #expect(out.primaryText == "63")
        #expect(out.status == "Read as octal")
    }

    @Test func decimal_from10_explicit() throws {
        let out = try run("number.decimal", "42", options: ["from": "10"])
        #expect(out.primaryText == "42")
        #expect(out.status == "Read as decimal")
    }

    @Test func hex_from16_withMatchingPrefix() throws {
        let out = try run("number.hex", "0xff", options: ["from": "16"])
        #expect(out.primaryText == "ff")
    }

    @Test func negative_decimal() throws {
        let out = try run("number.decimal", "-255")
        #expect(out.primaryText == "-255")
    }

    @Test func negative_hex_output() throws {
        let out = try run("number.hex", "-255")
        #expect(out.primaryText == "-ff")
    }

    @Test func negative_with_prefix_hex() throws {
        let out = try run("number.hex", "-255", options: ["prefix": "true"])
        #expect(out.primaryText == "-0xff")
    }

    @Test func leadingZeros() throws {
        let out = try run("number.hex", "000255")
        #expect(out.primaryText == "ff")
    }

    @Test func decimal_neverGetsPrefix() throws {
        let out = try run("number.decimal", "255", options: ["prefix": "true"])
        #expect(out.primaryText == "255")
    }

    @Test func fields_includeAllBases() throws {
        let out = try run("number.hex", "10")
        #expect(try field(out, id: "decimal") == "10")
        #expect(try field(out, id: "hex") == "a")
        #expect(try field(out, id: "binary") == "1010")
        #expect(try field(out, id: "octal") == "12")
    }

    @Test func fields_withPrefix() throws {
        let out = try run("number.hex", "10", options: ["prefix": "true"])
        #expect(try field(out, id: "decimal") == "10")
        #expect(try field(out, id: "hex") == "0xa")
        #expect(try field(out, id: "binary") == "0b1010")
        #expect(try field(out, id: "octal") == "0o12")
    }

    @Test func octal_command() throws {
        let out = try run("number.octal", "64")
        #expect(out.primaryText == "100")
    }

    @Test func binary_command() throws {
        let out = try run("number.binary", "10")
        #expect(out.primaryText == "1010")
    }

    @Test func affinity_hexForDecimal() throws {
        let cmd = try #require(NumberTools.commands.first { $0.id == "number.decimal" })
        let profileHex = InputProfile(isAttached: true, kinds: [.hex], primaryKind: .hex,
                                      byteCount: 4, lineCount: 1, isBlank: false)
        #expect(cmd.affinity(profileHex) == 70)

        let profileNumber = InputProfile(isAttached: true, kinds: [.number], primaryKind: .number,
                                         byteCount: 3, lineCount: 1, isBlank: false)
        #expect(cmd.affinity(profileNumber) == 0)
    }

    @Test func affinity_numberForHex() throws {
        let cmd = try #require(NumberTools.commands.first { $0.id == "number.hex" })
        let profile = InputProfile(isAttached: true, kinds: [.number], primaryKind: .number,
                                   byteCount: 3, lineCount: 1, isBlank: false)
        #expect(cmd.affinity(profile) == 60)
    }

    @Test func tooManyDigits() throws {
        let digits = String(repeating: "1", count: 4097)
        let result = try runResult("number.decimal", digits)
        if case .tooLarge(let msg) = result {
            #expect(msg == "Numbers can have at most 4,096 digits.")
        } else {
            Issue.record("Expected tooLarge, got \(result)")
        }
    }

    @Test func exactlyMaxDigits() throws {
        let digits = String(repeating: "1", count: 4096)
        let result = try runResult("number.decimal", digits)
        #expect(result.isSuccess)
    }

    @Test func underscoreAtStart() throws {
        let result = try runResult("number.decimal", "_123")
        #expect(result.isSuccess == false)
    }

    @Test func doubleUnderscore() throws {
        let result = try runResult("number.decimal", "1__2")
        #expect(result.isSuccess == false)
    }

    @Test func missingInput() throws {
        let cmd = try #require(NumberTools.commands.first { $0.id == "number.decimal" })
        if case .needsInput = cmd.run(ToolRequest(input: .none)) {} else {
            Issue.record("Expected needsInput")
        }
    }
}


@Suite struct NumberTrailingUnderscoreTests {
    @Test(arguments: [
        ("123_", "auto", 1, 4),
        ("123_", "10", 1, 4),
        ("ff_", "16", 1, 3),
        ("101_", "2", 1, 4),
        ("77_", "8", 1, 3),
        ("-123_", "auto", 1, 5),
        ("-0xff_", "auto", 1, 6),
        ("-0b101_", "auto", 1, 7),
        ("0o77_", "auto", 1, 5),
        ("  123_  ", "10", 1, 6),
        ("\n  -0xff_ \n", "16", 2, 8),
    ])
    func rejectsDanglingSeparator(input: String, base: String, line: Int, column: Int) {
        for command in NumberTools.commands {
            let result = command.run(ToolRequest(text: input, options: ["from": base]))
            guard case .invalid(let diagnostic) = result else {
                Issue.record("Expected invalid for \(command.id), got \(result)")
                continue
            }
            #expect(diagnostic.location?.line == line)
            #expect(diagnostic.location?.column == column)
        }
    }

    @Test func acceptsEmbeddedSeparators() throws {
        let command = try #require(NumberTools.commands.first { $0.id == "number.decimal" })
        #expect(command.run(ToolRequest(text: "1_000_000")).output?.primaryText == "1000000")
        #expect(command.run(ToolRequest(text: "0xff_00")).output?.primaryText == "65280")
    }
}

@Suite struct NumberLocationTests {
    @Test func locationsPointIntoTheOriginalInput() throws {
        let command = try #require(NumberTools.commands.first { $0.id == "number.hex" })
        guard case .invalid(let diagnostic) = command.run(ToolRequest(input: .text("  12g"))) else {
            Issue.record("Expected invalid"); return
        }
        #expect(diagnostic.location == TextLocation(line: 1, column: 5))
        guard case .invalid(let second) = command.run(ToolRequest(input: .text("\n 7z"))) else {
            Issue.record("Expected invalid"); return
        }
        #expect(second.location == TextLocation(line: 2, column: 3))
    }
}

@Suite struct NumberExplicitHexTests {
    /// Review P3: with Read as Hex, "0BEEF" is the hex number 0x0BEEF.
    @Test func explicitHexReadsLeadingZeroBAsDigits() throws {
        let command = try #require(NumberTools.commands.first { $0.id == "number.decimal" })
        let result = command.run(ToolRequest(input: .text("0BEEF"), options: ToolOptions(["from": "16"])))
        #expect(result.output?.primaryText == "48879")
        // Auto still treats 0b as a binary prefix.
        let auto = command.run(ToolRequest(input: .text("0b101")))
        #expect(auto.output?.primaryText == "5")
    }
}
