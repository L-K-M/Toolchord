import Testing
@testable import ToolchordCore

@Suite struct InputDetectorTests {
    private func kinds(_ text: String) -> Set<InputKind> { InputDetector.profile(for: text).kinds }
    private func label(_ text: String) -> String { InputDetector.profile(for: text).label }

    @Test func noInputAndBlankInputAreDistinct() {
        let none = InputDetector.profile(for: .none)
        #expect(!none.isAttached)
        let empty = InputDetector.profile(for: .text(""))
        #expect(empty.isAttached && empty.isBlank)
        #expect(empty.byteCount == 0)
        #expect(InputDetector.profile(for: "  \n ").isBlank)
    }

    @Test(arguments: [
        (#"{"a":1}"#, InputKind.json, "JSON"),
        ("[1, 2]", .json, "JSON"),
        ("[ ]", .json, "JSON"),
        ("[true, null]", .json, "JSON"),
        ("[\n  {\"a\": 1}\n]", .json, "JSON"),
        ("[1,", .json, "JSON"),
        ("{ broken", .json, "JSON"),
        ("<r><a/></r>", .xml, "XML"),
        ("eyJhbGciOiJub25lIn0.eyJleHAiOjB9.", .jwt, "JWT"),
        ("https://example.test/a?b=1", .url, "URL"),
        ("a=1&b=2", .queryString, "Query string"),
        ("?filter[name]=x&$top=10&flag", .queryString, "Query string"),
        ("0f8fad5b-d9cb-469f-a165-70867728950e", .uuid, "UUID"),
        ("1700000000", .unixTime, "Unix time"),
        ("1700000000000", .unixTime, "Unix time"),
        ("2024-01-01T12:00:00Z", .dateTime, "Date"),
        ("2024-01-01 12:00:00+01:00", .dateTime, "Date"),
        ("#ff8800", .hexColor, "Color"),
        ("rgb(1, 2, 3)", .color, "Color"),
        ("SGVsbG8gd29ybGQ=", .base64, "Base64"),
        ("8J-YgA_xyzAB", .base64URL, "Base64URL"),
        ("0xff", .number, "Number"),
        ("deadbeef", .hex, "Hex"),
        ("hello%20world", .percentEncoded, "URL-encoded text"),
        ("caf&eacute; &amp; more", .htmlEntities, "HTML entities"),
        (#""line\nbreak""#, .jsonStringLiteral, "JSON string"),
        ("Hello, World!", .words, "Text"),
        ("userName", .words, "Text"),
    ] as [(String, InputKind, String)])
    func detectsKind(text: String, kind: InputKind, expectedLabel: String) {
        #expect(kinds(text).contains(kind), "\(text) should be \(kind)")
        #expect(label(text) == expectedLabel, "\(text)")
    }

    @Test(arguments: [
        ("<!DOCTYPE html><html><body><p>Hi</p></body></html>", "HTML"),
        ("<!-- note -->\n<div class=\"a\"><p>Hello</p></div>", "HTML"),
        ("<p>Hello</p>", "HTML"),
        ("Hello <b>world</b>, and <i>you</i>", "HTML"),
        ("<?xml version=\"1.0\"?><rss><channel><title>T</title><link>x</link></channel></rss>", "XML"),
        ("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0\"/></svg>", "XML"),
        ("<my-widget><div>x</div></my-widget>", "XML"),
        ("<r><a/></r>", "XML"),
        ("Use the <div> element", "Text"),
        ("<!-- <div> -->\n<rss><channel/></rss>", "XML"),
        ("<!-- <config> -->\n<div>Hello</div>", "HTML"),
        ("<?xml version=\"1.0\"?>\n<!-- <p> -->\n<feed><title>T</title></feed>", "XML"),
        ("<title>Hello</title>", "HTML"),
        ("<link rel=\"stylesheet\" href=\"app.css\">", "HTML"),
        ("<data><item>1</item></data>", "XML"),
    ] as [(String, String)])
    func detectsHTML(text: String, expectedLabel: String) {
        #expect(label(text) == expectedLabel, "\(text)")
        #expect(kinds(text).contains(.html) == (expectedLabel == "HTML"), "\(text)")
    }

    @Test(arguments: [
        "# Title\n\nSome *emphasis* and a [link](https://example.com).",
        "```swift\nlet x = 1\n```",
        "| a | b |\n|---|---|\n| 1 | 2 |",
        "Read the [docs](https://example.com)",
        "See ![diagram](d.png)",
        "## Install\n\n- one\n- two",
        "**Bold** and `code`",
        "[docs]: https://example.com\n\n> Quote",
        "Use <kbd>Cmd</kbd> and <kbd>K</kbd>.\n\n## Keys\n\n- one",
        "[docs](https://example.com?a=1&b=2)",
        "**Bold** and ``a ` b``",
    ])
    func detectsMarkdown(text: String) {
        let profile = InputDetector.profile(for: text)
        #expect(profile.has(.markdown), "\(text)")
        #expect(profile.label == "Markdown", "\(text)")
        #expect(!profile.has(.html), "\(text)")
        #expect(profile.isPlainText)
    }

    @Test(arguments: [
        "Hello, World",
        "line one\nline two",
        "- milk\n- eggs",
        "- [x] done\n- [ ] todo",
        "def __init__(self):\n    # set up\n    self.a = 1",
        "# Install deps\nnpm install\n# Build\nnpm run build",
        "a**2 + b**2",
        "int *p = *q;",
        "items[0](x) and arr[1](y)",
        "snake_case_name and __dunder__",
        #"{"text": "**bold** and [x](y)"}"#,
        "https://example.com/a_*b*_",
    ])
    func ordinaryTextIsNotMarkdown(text: String) {
        #expect(!kinds(text).contains(.markdown), "\(text)")
    }

    @Test func specialCharactersAreNoticedButNeverTheLabel() {
        #expect(kinds("It’s here").contains(.specialCharacters))
        #expect(kinds("a\u{00A0}b").contains(.specialCharacters))
        #expect(kinds("zero\u{200B}width").contains(.specialCharacters))
        #expect(kinds(#"{"a":"“x”"}"#).isSuperset(of: [.json, .specialCharacters]))
        #expect(label("It’s here") == "Text")
        #expect(!kinds("plain text\r\nwith CRLF\ttab").contains(.specialCharacters))
        let blank = InputDetector.profile(for: "\u{00A0}\u{2028}")
        #expect(blank.isBlank && blank.has(.specialCharacters))
        #expect(!InputDetector.profile(for: " \n").has(.specialCharacters))
    }

    @Test func bracketedProseIsNotJSON() {
        #expect(!kinds("[docs](https://example.com) and more").contains(.json))
        #expect(!kinds("[nav] [home]").contains(.json))
        #expect(!kinds("[WIP] Fix the build").contains(.json))
    }

    @Test func plainWordsAreNotBase64() {
        #expect(!kinds("password").contains(.base64))
        #expect(!kinds("localhost").contains(.base64))
        #expect(!kinds("abcd").contains(.base64))
    }

    @Test(arguments: [
        "first_name", "max-width", "Content-Type", "X-Request-ID",
        "API_KEY_NAME", "x-request-id", "snake_case_identifier_here",
        "OAuth2Token", "iPhone15Pro", "version2Beta", "userId42",
        "SHA256Hash", "utf8String",
    ])
    func identifiersSuggestCaseConversion(text: String) throws {
        let profile = InputDetector.profile(for: text)
        #expect(profile.primaryKind == .words)
        #expect(!profile.has(.base64))
        #expect(!profile.has(.base64URL))
        let command = try #require(CaseTools.commands.first { $0.id == "case.camel" })
        #expect(command.affinity(profile) >= 30)
    }

    @Test(arguments: [
        ("Xk3_9aBq-LmZ2pQr7tUv0w", InputKind.base64URL),
        ("dGhpcyBpcyBhIHRlc3Q", .base64URL),
        ("eyJzdWIiOiIxMjM0NTY3ODkwIn0", .base64URL),
        ("SGVsbG8gV29ybGQh", .base64),
        ("Pd4tJD1k6aLPzqlRnwvBWH2eT30l1dO6", .base64),
        ("aGVsbG8=", .base64),
    ] as [(String, InputKind)])
    func encodedTokensKeepTheirKinds(text: String, kind: InputKind) {
        #expect(InputDetector.profile(for: text).primaryKind == kind)
    }

    @Test func shortNumbersAreNotTimestamps() {
        #expect(kinds("255").contains(.number))
        #expect(!kinds("255").contains(.unixTime))
    }

    @Test func dottedNamesAreNotJWTs() {
        #expect(!kinds("www.example.com").contains(.jwt))
        #expect(!kinds("mail.example.com").contains(.jwt))
        #expect(!kinds("1.2.3").contains(.jwt))
    }

    @Test func codeIsNotWords() {
        #expect(!kinds("if (a) { b }").contains(.words))
        #expect(!kinds("a < b").contains(.words))
    }

    @Test func plainTextFlag() {
        #expect(InputDetector.profile(for: "Hello, World").isPlainText)
        #expect(InputDetector.profile(for: "line one\nline two").isPlainText)
        #expect(!InputDetector.profile(for: #"{"a":1}"#).isPlainText)
        #expect(!InputDetector.profile(for: "1700000000").isPlainText)
        #expect(!InputDetector.profile(for: "").isPlainText)
        #expect(!InputProfile.none.isPlainText)
    }

    @Test func countsLinesAndBytes() {
        let profile = InputDetector.profile(for: "a\r\nb\nc\rd")
        #expect(profile.lineCount == 4)
        #expect(profile.kinds.contains(.multiline))
        #expect(InputDetector.profile(for: "é").byteCount == 2)
    }

    @Test func largeInputIsDetectedQuickly() {
        let big = "[" + String(repeating: "1,", count: 400_000) + "1]"
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = InputDetector.profile(for: big) }
        #expect(InputDetector.profile(for: big).kinds.contains(.json))
        #expect(elapsed < .seconds(2))
    }

    @Test func largeMarkupLikeInputIsDetectedQuickly() {
        let clock = ContinuousClock()
        let samples = [
            String(repeating: "- item with *stars* and `ticks`\n", count: 40_000),
            String(repeating: "<", count: 1_000_000),
            String(repeating: "[a](", count: 250_000),
            String(repeating: "**a ", count: 250_000),
            String(repeating: "\n", count: 1_000_000),
        ]
        for sample in samples {
            let elapsed = clock.measure { _ = InputDetector.profile(for: sample) }
            #expect(elapsed < .seconds(1), "\(sample.prefix(10))")
        }
    }
}
