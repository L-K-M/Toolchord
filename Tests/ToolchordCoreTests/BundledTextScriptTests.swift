import Testing
@testable import ToolchordCore

@Suite struct BundledTextScriptTests {
    private func run(_ id: String, _ input: String, options: [String: String] = [:]) throws -> ToolResult {
        let command = try #require(ToolCatalog.command(id: id))
        return command.run(ToolRequest(input: .text(input), options: ToolOptions(options)))
    }

    @Test(arguments: ["e228a1", "f0288cbc", "c2ff", "e28241", "f08080bf", "f4908080"])
    func hexRejectsMalformedUTF8(_ input: String) throws {
        #expect(try run("hex.decode", input) == .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text.")))
    }

    @Test func entityNamesDoNotResolveObjectPrototypeProperties() throws {
        let input = "&constructor; &hasOwnProperty; &hasOwnProperty; &toString;"
        let output = try #require(run("html.unescape", input).output)
        #expect(output.primaryText == input)
        #expect(output.warnings == [
            "Unknown entity “&constructor;” was left unchanged.",
            "Unknown entity “&hasOwnProperty;” was left unchanged.",
            "Unknown entity “&toString;” was left unchanged."
        ])
    }

    @Test(arguments: ["\u{85}", "\u{200B}", "\u{2028}", "\u{2029}"])
    func numericAndHexTrimmingPreservesFoundationWhitespace(_ space: String) throws {
        #expect(try run("hex.decode", space + "41" + space).output?.primaryText == "A")
        #expect(try run("number.decimal", space + "42" + space).output?.primaryText == "42")
        #expect(try run("color.hex", space + "#ff0000" + space).output?.primaryText == "#ff0000")
    }

    @Test(arguments: ["\u{200C}", "\u{200D}", "\u{FEFF}"])
    func invisibleCharactersDoNotBecomeNumericWhitespace(_ scalar: String) throws {
        for (id, input) in [("hex.decode", "41"), ("number.decimal", "42"), ("color.hex", "#ff0000")] {
            if case .invalid = try run(id, scalar + input) {} else {
                Issue.record("\(id) must reject the leading invisible character")
            }
        }
    }

    @Test func colorComponentsDoNotTrimLineBreaks() throws {
        if case .invalid = try run("color.hex", "rgb(255,\n0,0)") {} else {
            Issue.record("An interior newline is not horizontal component whitespace")
        }
        #expect(try run("color.hex", "rgb(255,\u{200B}0,0)").output?.primaryText == "#ff0000")
    }

    @Test func lineTrimmingUsesHorizontalFoundationWhitespace() throws {
        let output = try #require(run("lines.dedupe", "a\u{200B}\na", options: ["trim": "true"]).output)
        #expect(output.primaryText.hasSameUTF8(as: "a\u{200B}"))
        #expect(output.status == "Removed 1 duplicate")
    }

    @Test func caseBoundariesKeepUnicodeNumericTypes() throws {
        #expect(try run("case.snake", "一Beta").output?.primaryText == "一_beta")
        #expect(try run("case.title", "fooⅠBar").output?.primaryText == "FooⅠBar")
    }
    @Test func whitespaceGraphemesDoNotCreateWordsFromCombiningMarks() throws {
        let output = try #require(run("text.count", " \u{301} ").output)
        #expect(output.primaryText == "2")
        #expect(output.fields.first { $0.id == "words" }?.value == "0")
        #expect(output.fields.first { $0.id == "scalars" }?.value == "3")
    }
    @Test(arguments: ["number.decimal", "number.hex", "number.binary", "number.octal"])
    func numberFieldPrefixesFollowTheTargetCommand(_ id: String) throws {
        let output = try #require(run(id, "a", options: ["prefix": "true"]).output)
        let expected = id == "number.decimal" ? ["10", "a", "1010", "12"] : ["10", "0xa", "0b1010", "0o12"]
        #expect(output.fields.map(\.value) == expected)
    }
}
