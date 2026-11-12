import Foundation
import Testing
@testable import ToolchordCore

@Suite struct Base64ToolsTests {
    func run(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolResult {
        let command = try #require(Base64Tools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
    }

    @Test func fixtures() throws {
        let fixtures = [
            ("base64.encode", "✓", "4pyT"), ("base64.decode", "4pyT", "✓"),
            ("base64.encode", "😀", "8J+YgA=="), ("base64url.encode", "😀", "8J-YgA"),
            ("base64url.decode", "8J-YgA", "😀"), ("base64url.decode", "8J-YgA==", "😀"),
            ("base64.decode", "SGVsbG8=", "Hello"), ("base64url.decode", "SGVsbG8", "Hello"),
            ("base64url.decode", "SGVsbG8=", "Hello"),
        ]
        for (id, input, expected) in fixtures {
            #expect(try run(id, input).output?.primaryText == expected)
        }
        #expect(try run("base64.decode", "SGVs\nbG8=", options: ["ignoreWhitespace": "true"]).output?.primaryText == "Hello")
        #expect(try run("base64.decode", "SGVsbG8=").output?.status == "Decoded · 5 bytes")
        #expect(try run("base64.encode", "").output?.status == "Base64")
        #expect(try run("base64url.encode", "").output?.status == "Base64URL")
        for command in Base64Tools.commands {
            #expect(command.run(ToolRequest(input: .text(""))).output?.primaryText == "")
            if case .needsInput = command.run(ToolRequest(input: .none)) {} else { Issue.record("Expected missing input") }
        }
    }

    @Test func invalidFixturesAndLocations() throws {
        let fixtures: [(String, String, String, TextLocation?)] = [
            ("base64.decode", "Zh==", "The last character has nonzero padding bits, so this isn’t canonical Base64.", .init(line: 1, column: 2)),
            ("base64.decode", "/w==", "Decoded bytes are not UTF-8 text.", nil),
            ("base64.decode", "SGVsbG8", "Standard Base64 needs “=” padding. Add padding or use Decode Base64URL.", .init(line: 1, column: 8)),
            ("base64.decode", "SGVs bG8=", "Base64 contains whitespace. Turn on Ignore whitespace to decode wrapped text.", .init(line: 1, column: 5)),
            ("base64.decode", "SGVsbG8===", "Too much padding.", .init(line: 1, column: 10)),
            ("base64.decode", "S", "Base64 length is invalid. Check for missing or extra characters.", .init(line: 1, column: 1)),
            ("base64.decode", "SGV-bG8=", "Contains URL-safe characters (“-” or “_”). Use Decode Base64URL.", .init(line: 1, column: 4)),
            ("base64url.decode", "SGV+bG8", "Contains standard Base64 characters (“+” or “/”). Use Decode Base64.", .init(line: 1, column: 4)),
            ("base64.decode", "SG=sbG8=", "Padding “=” is only allowed at the end.", .init(line: 1, column: 3)),
            ("base64.decode", "AA%a", "Invalid Base64 character “%”.", .init(line: 1, column: 3)),
            ("base64.decode", "AA😀", "Invalid Base64 character “😀”.", .init(line: 1, column: 3)),
            ("base64url.decode", "AAB", "The last character has nonzero padding bits, so this isn’t canonical Base64.", .init(line: 1, column: 3)),
            ("base64url.decode", "AA=", "Base64 length is invalid. Check for missing or extra characters.", .init(line: 1, column: 3)),
            ("base64url.decode", "====", "Too much padding.", .init(line: 1, column: 3)),
        ]
        for (id, input, message, location) in fixtures {
            #expect(try run(id, input) == .invalid(ToolDiagnostic(message, at: location)))
        }
        let wrapped = try run("base64.decode", "AA\r\n%", options: ["ignoreWhitespace": "true"])
        #expect(wrapped == .invalid(ToolDiagnostic("Invalid Base64 character “%”.", at: .init(line: 2, column: 1))))
        #expect(try run("base64.decode", "AA\u{00A0}==", options: ["ignoreWhitespace": "true"]) ==
            .invalid(ToolDiagnostic("Invalid Base64 character “\u{00A0}”.", at: .init(line: 1, column: 3))))
        #expect(try run("base64.decode", " \t\r\n", options: ["ignoreWhitespace": "true"]).output?.primaryText == "")
    }

    @Test func surroundingWhitespaceIsIgnored() throws {
        // Tokens copied from a terminal or an editor usually end with a line break.
        let fixtures = [
            ("base64.decode", "SGVsbG8=\n"), ("base64.decode", "  SGVsbG8=\r\n"),
            ("base64.decode", "\u{00A0}SGVsbG8=\u{2028}"), ("base64url.decode", "SGVsbG8\n"),
            ("base64url.decode", "\tSGVsbG8=  "),
        ]
        for (id, input) in fixtures {
            #expect(try run(id, input).output?.primaryText == "Hello")
        }
        #expect(try run("base64.decode", " \n").output?.primaryText == "")
        // Whitespace inside the encoding still needs Ignore whitespace, and
        // locations keep pointing into the original input.
        #expect(try run("base64.decode", "\nSGVs bG8=\n") == .invalid(ToolDiagnostic(
            "Base64 contains whitespace. Turn on Ignore whitespace to decode wrapped text.", at: .init(line: 2, column: 5))))
        #expect(try run("base64.decode", "  SGVsbG8\n") == .invalid(ToolDiagnostic(
            "Standard Base64 needs “=” padding. Add padding or use Decode Base64URL.", at: .init(line: 1, column: 10))))
    }

    @Test func codecAPIAndRoundTrips() throws {
        // RFC 4648 vectors, independently specified for zero through six input bytes.
        let vectors = [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"),
                       ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")]
        for (text, encoded) in vectors {
            #expect(Base64Codec.encode(text.utf8, alphabet: .standard) == encoded)
            #expect(try Base64Codec.decode(encoded, alphabet: .standard).get() == Array(text.utf8))
        }
        for alphabet in [Base64Codec.Alphabet.standard, .url] {
            for text in ["Grüezi 👩🏽‍💻 日本語\r\n", "é", "e\u{0301}", "\0", String(repeating: "✓😀", count: 10000)] {
                let encoded = Base64Codec.encode(text.utf8, alphabet: alphabet)
                #expect(try Base64Codec.decode(encoded, alphabet: alphabet).get() == Array(text.utf8))
                let prefix = alphabet == .standard ? "base64" : "base64url"
                let commandEncoded = try #require(run("\(prefix).encode", text).output?.primaryText)
                #expect(try run("\(prefix).decode", commandEncoded).output?.primaryText == text)
            }
        }
        #expect(Base64Codec.decode("AA\r\n%", alphabet: .url, ignoreWhitespace: true) ==
            .failure(.init(message: "Invalid Base64 character “%”.", offset: 4)))
        // Foundation provides an independent encoder for every byte value and tail length.
        let binary = Array(UInt8.min...UInt8.max)
        for length in 0...binary.count {
            let bytes = binary.prefix(length)
            let standard = Data(bytes).base64EncodedString()
            let url = standard.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            #expect(Base64Codec.encode(bytes, alphabet: .standard) == standard)
            #expect(Base64Codec.encode(bytes, alphabet: .url) == url)
            #expect(try Base64Codec.decode(standard, alphabet: .standard).get() == Array(bytes))
            #expect(try Base64Codec.decode(url, alphabet: .url).get() == Array(bytes))
        }
    }

    @Test func limitsCancellationAndAffinities() throws {
        for command in Base64Tools.commands {
            #expect(command.run(ToolRequest(input: .text("hello"), cancellation: .init { true })) == .cancelled)
            #expect(command.run(ToolRequest(input: .text(""), cancellation: .init { true })) == .cancelled)
            let input = command.id.hasSuffix("encode") ? "hello" : "SGVsbG8="
            let limits = ToolLimits(maxOutputBytes: 4)
            #expect(command.run(ToolRequest(input: .text(input), limits: limits)) == .tooLarge(limits.outputLimitMessage))
            let boundary = command.id.hasSuffix("encode") ? "Zg==" : "f"
            let outputInput = command.id.hasSuffix("encode") ? "f" : "Zg=="
            let expected = command.id == "base64url.encode" ? "Zg" : boundary
            #expect(command.run(ToolRequest(input: .text(outputInput), limits: .init(maxOutputBytes: expected.utf8.count))).output?.primaryText == expected)
        }
        let standard = InputProfile(isAttached: true, kinds: [.base64], primaryKind: .base64, byteCount: 4, lineCount: 1, isBlank: false)
        #expect(Base64Tools.commands.first { $0.id == "base64.decode" }?.affinity(standard) == 95)
        #expect(Base64Tools.commands.first { $0.id == "base64url.decode" }?.affinity(standard) == 0)
    }
}
