import Foundation
import Testing
@testable import ToolchordCore

@Suite struct JSONToolsTests {
    func result(_ id: String, _ text: String, options: [String: String] = [:],
                limits: ToolLimits = .standard, cancellation: CancellationCheck = .never) throws -> ToolResult {
        let command = try #require(JSONTools.commands.first { $0.id == "json.\(id)" })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(options), limits: limits, cancellation: cancellation))
    }

    func output(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolOutput {
        let value = try result(id, text, options: options)
        return try #require(value.output, "Expected success, got \(value)")
    }

    @Test func preservesNumberAndStringTokens() throws {
        #expect(try output("minify", #"{"n":9007199254740993, "e":1e+02, "z":-0}"#).primaryText
                == #"{"n":9007199254740993,"e":1e+02,"z":-0}"#)
        let value = try output("minify", #"{"a":1, "a":2, "s":"a  b"}"#)
        #expect(value.primaryText == #"{"a":1,"a":2,"s":"a  b"}"#)
        #expect(value.warnings == ["Duplicate member name “a” at line 1, column 9. Some parsers keep only the last value."])
        #expect(try output("format", #""\u00e9\n""#).primaryText == #""\u00e9\n""#)
        #expect(try output("minify", #"[-0,1E-99999999999999999999,1.0000,"\/\uD800"]"#).primaryText
                == #"[-0,1E-99999999999999999999,1.0000,"\/\uD800"]"#)
    }

    @Test func formattingFixtures() throws {
        #expect(try output("format", "true").primaryText == "true")
        #expect(try output("format", #"{"a":[1,2,{"b":null}],"c":{},"d":[ ]}"#).primaryText == """
        {
          "a": [
            1,
            2,
            {
              "b": null
            }
          ],
          "c": {},
          "d": []
        }
        """)
        #expect(try output("format", "[1,[2]]", options: ["indent": "tab"]).primaryText == "[\n\t1,\n\t[\n\t\t2\n\t]\n]")
        #expect(try output("format", #"{"k":"v"}"#, options: ["indent": "4"]).primaryText == "{\n    \"k\": \"v\"\n}")
        #expect(try output("format", " \r\n[ ]\t").primaryText == "[]")
        #expect(try output("format", " { } ").primaryText == "{}")
        let text = "  {\"a\":1}  \n"
        let validated = try output("validate", text)
        #expect(validated.primaryText == text)
        #expect(validated.status == "Valid JSON")
        #expect(validated.syntax == .json)
        #expect(validated.fields.isEmpty)
    }

    @Test(arguments: [
        ("{\n  \"a\": }", "Expected a value, found “}”.", 2, 8),
        ("{\r\n  \"a\": }", "Expected a value, found “}”.", 2, 8),
        ("{\r  \"a\": }", "Expected a value, found “}”.", 2, 8),
        (#"{"a":1,}"#, "Remove the trailing comma before “}”.", 1, 7),
        ("[1, ]", "Remove the trailing comma before “]”.", 1, 3),
        ("[0,🚀]", "Expected a value, found “🚀”.", 1, 4),
        ("[1 2]", "Expected “,” or “]”.", 1, 4),
        (#"{"a":1 "b":2}"#, "Expected “,” or “}”.", 1, 8),
        ("// c\n{}", "Comments aren’t allowed in JSON.", 1, 1),
        ("[/*comment*/1]", "Comments aren’t allowed in JSON.", 1, 2),
        ("{} //comment", "Comments aren’t allowed in JSON.", 1, 4),
        ("\u{FEFF}{}", "Remove the byte order mark (U+FEFF) at the start of the input.", 1, 1),
        (#"{"é": x}"#, "Invalid literal. Use true, false, or null.", 1, 7),
        ("[01]", "Numbers can’t have leading zeros.", 1, 2),
        ("[-01]", "Numbers can’t have leading zeros.", 1, 3),
        ("", "Expected a JSON value.", 1, 1),
        (" \r\n\t", "Expected a JSON value.", 2, 2),
        ("'x'", "Use double quotes for JSON strings.", 1, 1),
        ("{'x':1}", "Use double quotes for JSON strings.", 1, 2),
        ("{name:1}", "Member names must be double-quoted strings.", 1, 2),
        (#"{"a" 1}"#, "Expected “:” after the member name.", 1, 6),
        ("tru", "Invalid literal. Use true, false, or null.", 1, 1),
        ("nul", "Invalid literal. Use true, false, or null.", 1, 1),
        ("True", "Invalid literal. Use true, false, or null.", 1, 1),
        ("NaN", "“NaN” isn’t valid JSON. Use null or a string.", 1, 1),
        ("Infinity", "“Infinity” isn’t valid JSON. Use null or a string.", 1, 1),
        ("-Infinity", "“-Infinity” isn’t valid JSON. Use null or a string.", 1, 1),
        ("+1", "Numbers can’t start with “+”.", 1, 1),
        ("1.", "Expected a digit after “.”.", 1, 2),
        (".5", "Expected a digit before “.”.", 1, 1),
        ("1e", "Expected a digit in the exponent.", 1, 3),
        ("1e+", "Expected a digit in the exponent.", 1, 4),
        ("\"abc", "Unterminated string.", 1, 1),
        ("\"abc\\", "Unterminated string.", 1, 1),
        ("\"a\nb\"", "Escape control character U+000A in this string.", 1, 3),
        (#""\x""#, #"Invalid escape “\x”."#, 1, 2),
        (#""\u123""#, #"Expected four hex digits after “\u”."#, 1, 2),
        (#""\u1x34""#, #"Expected four hex digits after “\u”."#, 1, 2),
        ("{", "Expected “}” before the end of the input.", 1, 2),
        ("[1", "Expected “]” before the end of the input.", 1, 3),
        ("true false", "Unexpected text after the JSON value.", 1, 6),
        ("[1\u{00A0}2]", "Expected “,” or “]”.", 1, 3),
    ])
    func syntaxErrors(_ fixture: (String, String, Int, Int)) throws {
        let (text, message, line, column) = fixture
        #expect(try result("format", text) == .invalid(ToolDiagnostic(message, at: TextLocation(line: line, column: column))))
    }

    @Test func rawAllowedScalarsAndScalarRoots() throws {
        for text in ["true", "false", "null", "1", "-0", "1.2e-3", #""x""#, "\"\u{007F}\u{2028}\u{2029}\"", #""\ud800""#, #""\uDC00""#] {
            #expect(try output("minify", " \(text)\n").primaryText == text)
        }
    }

    @Test func duplicateNamesAreDecodedAndScoped() throws {
        let text = #"{"a":1,    "\u0061":2,"nested":{"a":3},"other":{"a":4}}"#
        for id in ["format", "minify", "validate"] {
            #expect(try output(id, text).warnings == ["Duplicate member name “a” at line 1, column 12. Some parsers keep only the last value."])
        }
        #expect(try output("validate", #"{"😀":1,"\ud83d\ude00":2}"#).warnings.count == 1)
        #expect(try output("validate", #"{"\uD800":1,"\ud800":2}"#).warnings.count == 1)
        let ordinaryNames = #"{"constructor":0,"__proto__":1,"toString":2,"constructor":3}"#
        let nameWarnings = try output("validate", ordinaryNames).warnings
        #expect(nameWarnings.count == 1)
        #expect(nameWarnings.first?.contains("“constructor”") == true)
        // JSON names compare code points, without Unicode normalization.
        #expect(try output("validate", "{\"é\":1,\"e\u{0301}\":2}").warnings.isEmpty)
        #expect(try output("validate", "{\r\n\"é\":1,\r\n\"é\":2}").warnings
                == ["Duplicate member name “é” at line 3, column 1. Some parsers keep only the last value."])
        let repeated = "{" + Array(repeating: "\"a\":1", count: 9).joined(separator: ",") + "}"
        let warnings = try output("validate", repeated).warnings
        #expect(warnings.count == 6)
        #expect(warnings[0] == "Duplicate member name “a” at line 1, column 8. Some parsers keep only the last value.")
        #expect(warnings[4] == "Duplicate member name “a” at line 1, column 32. Some parsers keep only the last value.")
        #expect(warnings[5] == "…and 3 more duplicate member names.")
    }

    @Test func escapeFixtures() throws {
        let input = "He said \"hi\"\n\tC:\\path"
        let escaped = #"He said \"hi\"\n\tC:\\path"#
        let quoted = try output("escapeString", input)
        #expect(quoted.primaryText == "\"" + escaped + "\"")
        #expect(quoted.status == "Escaped")
        #expect(quoted.syntax == .json)
        let body = try output("escapeString", input, options: ["quotes": "false"])
        #expect(body.primaryText == escaped)
        #expect(body.syntax == .plain)
        #expect(try output("escapeString", "\u{0001}").primaryText == #""\u0001""#)
        #expect(try output("escapeString", "").primaryText == "\"\"")
        #expect(try output("escapeString", "", options: ["quotes": "false"]).primaryText == "")
        #expect(try output("escapeString", "\u{0000}\u{0008}\u{000C}\n\r\t\u{001F}/é😀\u{2028}\u{2029}").primaryText
                == #""\u0000\b\f\n\r\t\u001f/é😀\u2028\u2029""#)
        #expect(try output("escapeString", "a\n").primaryText == #""a\n""#)
        #expect(try output("escapeString", "a\n", options: ["quotes": "false"]).primaryText == #"a\n"#)
    }

    @Test func unescapeFixtures() throws {
        let unescaped = try output("unescapeString", #""He said \"hi\"\n""#)
        #expect(unescaped.primaryText == "He said \"hi\"\n")
        #expect(unescaped.status == "Unescaped")
        #expect(unescaped.syntax == .plain)
        #expect(try output("unescapeString", #"a\tb"#).primaryText == "a\tb")
        #expect(try output("unescapeString", #"\ud83d\ude00"#).primaryText == "😀")
        #expect(try output("unescapeString", #"\"\\\/\b\f\n\r\t\u0041\u00e9"#).primaryText == "\"\\/\u{0008}\u{000C}\n\r\tAé")
        #expect(try output("unescapeString", "").primaryText == "")
        #expect(try output("unescapeString", "\"\"").primaryText == "")
        #expect(try output("unescapeString", "  \t ").primaryText == "  \t ")
        #expect(try output("unescapeString", "  \"a\" \r\n").primaryText == "a")
        #expect(try output("unescapeString", "\u{00A0}\"a\"\u{00A0}").primaryText == "a")
        #expect(try output("unescapeString", "\"a\nb\"").primaryText == "a\nb")
        #expect(try output("unescapeString", "a\"b").primaryText == "a\"b")
        #expect(try output("unescapeString", "\"abc").primaryText == "\"abc")
        #expect(try output("unescapeString", "\"").primaryText == "\"")
    }

    @Test(arguments: [
        (#"\ud800"#, #"Unpaired surrogate “\ud800” can’t be decoded to text."#, 1, 1),
        (#"\udc00"#, #"Unpaired surrogate “\udc00” can’t be decoded to text."#, 1, 1),
        (#"\uD800\u0041"#, #"Unpaired surrogate “\uD800” can’t be decoded to text."#, 1, 1),
        (#""a"b""#, "Unescaped “\"” inside the string.", 1, 3),
        (" \r\n \"é\\x\" ", #"Invalid escape “\x”."#, 2, 4),
        (#"\u12"#, #"Expected four hex digits after “\u”."#, 1, 1),
        (#"\uWXYZ"#, #"Expected four hex digits after “\u”."#, 1, 1),
        (#"\x"#, #"Invalid escape “\x”."#, 1, 1),
    ])
    func unescapeErrors(_ fixture: (String, String, Int, Int)) throws {
        let (text, message, line, column) = fixture
        #expect(try result("unescapeString", text) == .invalid(ToolDiagnostic(message, at: TextLocation(line: line, column: column))))
    }

    @Test func depthAndOutputLimits() throws {
        let valid = String(repeating: "[", count: 128) + String(repeating: "]", count: 128)
        #expect(try result("format", valid).isSuccess)
        let tooDeep = "[" + valid + "]"
        #expect(try result("format", tooDeep) == .tooLarge(ToolLimits.standard.nestingLimitMessage))
        let limits = ToolLimits(maxOutputBytes: 3, maxNestingDepth: 1)
        #expect(try result("minify", "[1]", limits: limits).output?.primaryText == "[1]")
        #expect(try result("format", "[1]", limits: limits) == .tooLarge(limits.outputLimitMessage))
        #expect(try result("validate", " 1  ", limits: limits) == .tooLarge(limits.outputLimitMessage))
        #expect(try result("minify", "[[]]", limits: limits) == .tooLarge(limits.nestingLimitMessage))
        #expect(try result("escapeString", "ab", limits: limits) == .tooLarge(limits.outputLimitMessage))
        #expect(try result("unescapeString", #"\ud83d\ude00"#, limits: limits) == .tooLarge(limits.outputLimitMessage))
        let zero = ToolLimits(maxOutputBytes: 0)
        #expect(try result("unescapeString", "", limits: zero).output?.primaryText == "")
        #expect(try result("escapeString", "", limits: zero) == .tooLarge(zero.outputLimitMessage))
    }

    @Test func missingInputAndCancellation() throws {
        for command in JSONTools.commands {
            if case .needsInput = command.run(ToolRequest(input: .none)) {} else { Issue.record("Expected needsInput for \(command.id)") }
            #expect(command.run(ToolRequest(input: .text("[1]"), cancellation: CancellationCheck { true })) == .cancelled)
        }
        let text = String(repeating: "a", count: (1 << 20) + 1)
        #expect(try result("escapeString", text) == .tooLarge(ToolLimits.standard.inputLimitMessage))
        #expect(try result("minify", "{}", cancellation: CancellationCheck { true }) == .cancelled)
    }

    @Test func oneMiBDocumentAndRoundTrips() throws {
        // Exactly 1 MiB: quotes add two bytes; the body has no escapes.
        let megabyte = "\"" + String(repeating: "a", count: (1 << 20) - 2) + "\""
        #expect(try output("format", megabyte).primaryText == megabyte)
        // A token-heavy document exercises the formatter's output loop as well.
        let many = "[" + Array(repeating: "0", count: 100_000).joined(separator: ",") + "]"
        for text in [many, #" {"x":[true,false,null,-0,1.00E+03],"x":"\uD800"} "#, "[{},[],[1,[2]],\"é😀\"]", "1e+02"] {
            let formatted = try output("format", text).primaryText
            #expect(try output("minify", formatted).primaryText == output("minify", text).primaryText)
        }
        for text in ["", "é😀\n\t\u{0000}", "\"\\/\u{2028}\u{2029}"] {
            let escaped = try output("escapeString", text).primaryText
            #expect(try output("unescapeString", escaped).primaryText == text)
        }
    }

    @Test func minifiesEveryRootKind() throws {
        for text in ["{}", "[]", #""x""#, "1", "null"] {
            #expect(try output("minify", text).primaryText == text)
        }
    }

    @Test func metadataAndAffinity() throws {
        #expect(JSONTools.commands.map(\.id) == ["json.format", "json.minify", "json.validate", "json.escapeString", "json.unescapeString"])
        let json = InputProfile(isAttached: true, kinds: [.json], primaryKind: .json, byteCount: 2, lineCount: 1, isBlank: false)
        let literal = InputProfile(isAttached: true, kinds: [.jsonStringLiteral, .escapedText], primaryKind: .jsonStringLiteral, byteCount: 2, lineCount: 1, isBlank: false)
        let escaped = InputProfile(isAttached: true, kinds: [.escapedText], primaryKind: .escapedText, byteCount: 2, lineCount: 1, isBlank: false)
        #expect(JSONTools.commands.map { $0.affinity(json) } == [100, 85, 70, 0, 0])
        #expect(JSONTools.commands.last?.affinity(literal) == 90)
        #expect(JSONTools.commands.last?.affinity(escaped) == 75)
        #expect(JSONTools.commands.map { $0.affinity(.none) } == [0, 0, 0, 0, 0])
        #expect(JSONTools.commands.allSatisfy { $0.group == .json })
        #expect(JSONTools.commands[3].icon == .glyph("\\\""))
        #expect(try output("format", "[1]", options: ["indent": "invalid"]).primaryText == "[\n  1\n]")
    }
}
