import Foundation
import Testing
@testable import ToolchordCore

@Suite struct CaseToolsTests {

    // MARK: - Helpers

    private func run(_ id: String, _ text: String) throws -> ToolOutput {
        let command = try #require(CaseTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    // MARK: - Basic fixtures from brief

    @Test func camelHelloWorld() throws {
        #expect(try run("case.camel", "hello world").primaryText == "helloWorld")
    }

    @Test func pascalHelloWorld() throws {
        #expect(try run("case.pascal", "hello world").primaryText == "HelloWorld")
    }

    @Test func snakeHelloWorld() throws {
        #expect(try run("case.snake", "hello world").primaryText == "hello_world")
    }

    @Test func kebabHelloWorld() throws {
        #expect(try run("case.kebab", "hello world").primaryText == "hello-world")
    }

    @Test func constantHelloWorld() throws {
        #expect(try run("case.constant", "hello world").primaryText == "HELLO_WORLD")
    }

    @Test func titleHelloWorld() throws {
        #expect(try run("case.title", "hello world").primaryText == "Hello World")
    }

    @Test func sentenceHelloWorld() throws {
        #expect(try run("case.sentence", "hello world").primaryText == "Hello world")
    }

    @Test func slugHelloWorld() throws {
        #expect(try run("case.slug", "hello world").primaryText == "hello-world")
    }

    @Test(arguments: [
        ("hello world", "Hello World"),
        ("the_quick-brownFox", "The Quick Brown Fox"),
        ("it's a test, really. NASA and iPhone rock", "It's A Test, Really. NASA And iPhone Rock"),
        ("HELLO WORLD", "Hello World"),
        ("don’t stop", "Don’t Stop"),
        ("élan vital", "Élan Vital"),
        ("hello\tworld  again", "Hello\tWorld  Again"),
        ("a b\r\nc d", "A B\r\nC D"),
        ("helloWorld", "Hello World"),
        ("  \t!?🙂  ", "  \t!?🙂  "),
        ("“123élan” 🙂 cafe\u{301} + macOS McDonald API", "“123Élan” 🙂 Cafe\u{301} + macOS McDonald API"),
        ("hello_world prose", "Hello_World Prose")
    ])
    func titlePreservesProse(input: String, expected: String) throws {
        #expect(try run("case.title", input).primaryText == expected)
    }

    @Test(arguments: [
        ("hello world", "Hello world"),
        ("Hello world. This is me, isn't it?", "Hello world. This is me, isn't it?"),
        ("HELLO WORLD. HOW ARE YOU?", "Hello world. How are you?"),
        ("the NASA launch was great! i agree.", "The NASA launch was great! I agree."),
        ("check the iPhone settings", "Check the iPhone settings"),
        ("the_quick-brownFox", "The quick brown fox"),
        ("hello world foo", "Hello world foo"),
        ("helloWorld", "Hello world"),
        ("say \"hello.\" then go!)] next? ’” again", "Say \"hello.\" Then go!)] Next? ’” Again"),
        ("wait.no change!still here? yes", "Wait.no change!still here? Yes"),
        ("123élan 🙂 I AGREE, i don’t mind.\tNEXT", "123Élan 🙂 I AGREE, I don’t mind.\tNEXT"),
        ("yes i'm sure, and i’ll go. ice is cold", "Yes I'm sure, and I’ll go. Ice is cold"),
        ("  \t!?🙂  ", "  \t!?🙂  ")
    ])
    func sentencePreservesProse(input: String, expected: String) throws {
        #expect(try run("case.sentence", input).primaryText == expected)
    }

    // MARK: - CamelCase parsing fixtures

    @Test func snakeXMLHttpRequest() throws {
        #expect(try run("case.snake", "XMLHttpRequest").primaryText == "xml_http_request")
    }

    @Test func camelXMLHttpRequest() throws {
        #expect(try run("case.camel", "XMLHttpRequest").primaryText == "xmlHttpRequest")
    }

    @Test func kebabHTTPServer() throws {
        #expect(try run("case.kebab", "HTTPServer").primaryText == "http-server")
    }

    @Test func snakeUserID() throws {
        #expect(try run("case.snake", "userID").primaryText == "user_id")
    }

    @Test func snakeVersion2Beta() throws {
        #expect(try run("case.snake", "version2Beta").primaryText == "version2_beta")
    }

    // MARK: - Mixed separator fixtures

    @Test func camelLeadingTrailingSpaces() throws {
        #expect(try run("case.camel", "  leading and trailing  ").primaryText == "leadingAndTrailing")
    }

    @Test func camelMixedSeparators() throws {
        #expect(try run("case.camel", "user_name-first.last").primaryText == "userNameFirstLast")
    }

    @Test func titleMixedInput() throws {
        #expect(try run("case.title", "the_quick-brownFox").primaryText == "The Quick Brown Fox")
    }

    // MARK: - Constant case with digits

    @Test func constantWithDigits() throws {
        #expect(try run("case.constant", "api key v2").primaryText == "API_KEY_V2")
    }

    // MARK: - Slug transliteration fixtures

    @Test func slugFrenchAccents() throws {
        #expect(try run("case.slug", "Crème brûlée à la carte!").primaryText == "creme-brulee-a-la-carte")
    }

    @Test func slugGermanSharpS() throws {
        #expect(try run("case.slug", "Straße & Co.").primaryText == "strasse-co")
    }

    // MARK: - Multi-line fixtures

    @Test func camelMultilineLF() throws {
        #expect(try run("case.camel", "foo bar\nbaz qux").primaryText == "fooBar\nbazQux")
    }

    @Test func snakeMultilineCRLF() throws {
        #expect(try run("case.snake", "foo bar\r\nbaz qux\r\n").primaryText == "foo_bar\r\nbaz_qux\r\n")
    }

    // MARK: - Lower / Upper fixtures

    @Test func lowerUnicode() throws {
        #expect(try run("case.lower", "ÉCOLE Normale").primaryText == "école normale")
    }

    @Test func upperUnicode() throws {
        #expect(try run("case.upper", "école normale 2").primaryText == "ÉCOLE NORMALE 2")
    }

    // MARK: - Empty input

    @Test func camelEmptyInput() throws {
        let output = try run("case.camel", "")
        #expect(output.primaryText == "")
    }

    @Test func pascalEmptyInput() throws {
        let output = try run("case.pascal", "")
        #expect(output.primaryText == "")
    }

    @Test func snakeEmptyInput() throws {
        let output = try run("case.snake", "")
        #expect(output.primaryText == "")
    }

    @Test func kebabEmptyInput() throws {
        let output = try run("case.kebab", "")
        #expect(output.primaryText == "")
    }

    @Test func constantEmptyInput() throws {
        let output = try run("case.constant", "")
        #expect(output.primaryText == "")
    }

    @Test func titleEmptyInput() throws {
        let output = try run("case.title", "")
        #expect(output.primaryText == "")
    }

    @Test func sentenceEmptyInput() throws {
        let output = try run("case.sentence", "")
        #expect(output.primaryText == "")
    }

    @Test func lowerEmptyInput() throws {
        let output = try run("case.lower", "")
        #expect(output.primaryText == "")
    }

    @Test func upperEmptyInput() throws {
        let output = try run("case.upper", "")
        #expect(output.primaryText == "")
    }

    @Test func slugEmptyInput() throws {
        let output = try run("case.slug", "")
        #expect(output.primaryText == "")
    }

    // MARK: - Unicode capitalization

    @Test func pascalUnicode() throws {
        #expect(try run("case.pascal", "élan vital").primaryText == "ÉlanVital")
    }

    // MARK: - Status labels

    @Test func statusLabels() throws {
        #expect(try run("case.camel", "x").status == "camelCase")
        #expect(try run("case.pascal", "x").status == "PascalCase")
        #expect(try run("case.snake", "x").status == "snake_case")
        #expect(try run("case.kebab", "x").status == "kebab-case")
        #expect(try run("case.constant", "x").status == "CONSTANT_CASE")
        #expect(try run("case.title", "x").status == "Title Case")
        #expect(try run("case.sentence", "x").status == "Sentence case")
        #expect(try run("case.lower", "x").status == "lowercase")
        #expect(try run("case.upper", "x").status == "UPPERCASE")
        #expect(try run("case.slug", "x").status == "Slug")
    }

    // MARK: - Missing input

    @Test func missingInputAsksForText() throws {
        let command = try #require(CaseTools.commands.first)
        if case .needsInput = command.run(ToolRequest(input: .none)) {} else {
            Issue.record("Expected needsInput")
        }
    }

    // MARK: - Command count and IDs

    @Test func commandCount() throws {
        #expect(CaseTools.commands.count == 10)
    }

    @Test func allCommandIDsPresent() throws {
        let ids = Set(CaseTools.commands.map { $0.id })
        let expected = Set([
            "case.camel", "case.pascal", "case.snake", "case.kebab",
            "case.constant", "case.title", "case.sentence", "case.lower",
            "case.upper", "case.slug"
        ])
        #expect(ids == expected)
    }

    // MARK: - Group, icon, copy noun, affinity

    @Test func commandMetadata() throws {
        for command in CaseTools.commands {
            #expect(command.group == .textCase)
            #expect(command.icon == .glyph("Aa"))
            #expect(command.copyNoun(ToolOptions()) == "text")
        }
    }

    @Test func affinityForWords() throws {
        let profile = InputProfile(
            isAttached: true,
            kinds: [.words],
            primaryKind: .words,
            byteCount: 5,
            lineCount: 1,
            isBlank: false
        )
        for command in CaseTools.commands {
            #expect(command.affinity(profile) == 40)
        }
    }

    @Test func affinityForNonWords() throws {
        let profile = InputProfile(
            isAttached: true,
            kinds: [.json],
            primaryKind: .json,
            byteCount: 5,
            lineCount: 1,
            isBlank: false
        )
        for command in CaseTools.commands {
            #expect(command.affinity(profile) == 0)
        }
    }

    // MARK: - Edge cases

    @Test func singleWordCamel() throws {
        #expect(try run("case.camel", "hello").primaryText == "hello")
    }

    @Test func singleWordPascal() throws {
        #expect(try run("case.pascal", "hello").primaryText == "Hello")
    }

    @Test func allWhitespaceLine() throws {
        // A line with only spaces produces no words, so output is empty for that line
        #expect(try run("case.camel", "   ").primaryText == "")
    }

    @Test func onlyLineBreaks() throws {
        #expect(try run("case.camel", "\n\n").primaryText == "\n\n")
    }

    @Test func lowerPreservesNonLetters() throws {
        #expect(try run("case.lower", "Hello, World! 123").primaryText == "hello, world! 123")
    }

    @Test func upperPreservesNonLetters() throws {
        #expect(try run("case.upper", "hello, world! 123").primaryText == "HELLO, WORLD! 123")
    }

    @Test func slugOnlyPunctuation() throws {
        #expect(try run("case.slug", "!@#$%").primaryText == "")
    }

    @Test func slugWithNumbers() throws {
        #expect(try run("case.slug", "test 123 foo").primaryText == "test-123-foo")
    }

    @Test func camelAllCaps() throws {
        #expect(try run("case.camel", "HELLO").primaryText == "hello")
    }

    @Test func snakeAllCaps() throws {
        #expect(try run("case.snake", "HELLO").primaryText == "hello")
    }

    @Test func constantAllLower() throws {
        #expect(try run("case.constant", "hello").primaryText == "HELLO")
    }

    @Test func sentenceSingleWord() throws {
        #expect(try run("case.sentence", "hello").primaryText == "Hello")
    }

    @Test func sentenceMultipleWords() throws {
        #expect(try run("case.sentence", "hello world foo").primaryText == "Hello world foo")
    }

    // MARK: - Output limit

    @Test func outputExceedsLimit() throws {
        let limits = ToolLimits(maxInputBytes: 1 << 20, maxOutputBytes: 10, maxNestingDepth: 128)
        let command = try #require(CaseTools.commands.first { $0.id == "case.upper" })
        let result = command.run(ToolRequest(
            input: .text("hello world extra"),
            limits: limits
        ))
        if case .tooLarge = result {} else {
            Issue.record("Expected tooLarge, got \(result)")
        }
    }
}

@Suite struct CaseToolsReviewTests {
    @Test func decomposedAccentsStayInTheirWord() throws {
        let command = try #require(CaseTools.commands.first { $0.id == "case.snake" })
        let output = try #require(command.run(ToolRequest(input: .text("Cafe\u{301} Menu"))).output)
        #expect(output.primaryText == "cafe\u{301}_menu")
    }

    @Test func cancellationIsReported() throws {
        let command = try #require(CaseTools.commands.first { $0.id == "case.camel" })
        let text = String(repeating: "a b\n", count: 5_000)
        let result = command.run(ToolRequest(input: .text(text), cancellation: CancellationCheck { true }))
        #expect(result == .cancelled)
    }
}
