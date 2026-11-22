import Foundation
import Testing
@testable import ToolchordCore

@Suite struct URLToolsTests {
    func command(_ id: String) throws -> ToolCommand {
        try #require(URLTools.commands.first { $0.id == "url.\(id)" })
    }

    func run(_ id: String, _ text: String, mode: String = "uri") throws -> ToolOutput {
        let result = try command(id).run(ToolRequest(input: .text(text), options: ToolOptions(["mode": mode])))
        return try #require(result.output, "Expected success, got \(result)")
    }

    func invalid(_ id: String, _ text: String) throws -> ToolDiagnostic {
        let result = try command(id).run(ToolRequest(input: .text(text)))
        guard case .invalid(let diagnostic) = result else {
            Issue.record("Expected invalid, got \(result)")
            throw TestFailure.unexpectedResult
        }
        return diagnostic
    }
    enum TestFailure: Error { case unexpectedResult }

    @Test func encodeAndDecodeFixtures() throws {
        #expect(try run("encode", "a b&c=d/é~").primaryText == "a%20b%26c%3Dd%2F%C3%A9~")
        #expect(try run("encode", "AZaz09-._~!*'()+%").primaryText == "AZaz09-._~%21%2A%27%28%29%2B%25")
        #expect(try run("decode", "a+b%20c%252F").primaryText == "a+b c%2F")
        #expect(try run("decode", "%EF%BB%BFx").primaryText == "x")
        #expect(try run("decode", "%c3%a9").primaryText == "é")
        #expect(try run("encode", "").primaryText == "")
        #expect(try run("decode", "").primaryText == "")
        #expect(try run("encode", "").status == "Encoded")
        #expect(try run("decode", "").status == "Decoded")
    }

    @Test func unicodeRoundTrip() throws {
        // Includes scalar boundaries, combining marks, non-BMP text, and controls.
        let text = "\u{0}\t\r\n é e\u{301} 中文 ✓ 🧑🏽‍💻 \u{2028}\u{2029}\u{10FFFF} %+&=/"
        let encoded = try run("encode", text).primaryText
        #expect(try run("decode", encoded).primaryText == text)
    }

    @Test func orderedParametersAndComponents() throws {
        let output = try run("inspect", "https://example.test/?a=1&a=2&empty=&flag&=x#end")
        #expect(output.primaryText == "[\n  {\"name\": \"a\", \"value\": \"1\"},\n  {\"name\": \"a\", \"value\": \"2\"},\n  {\"name\": \"empty\", \"value\": \"\"},\n  {\"name\": \"flag\", \"value\": \"\"},\n  {\"name\": \"\", \"value\": \"x\"}\n]")
        #expect(output.fields.map(\.id) == ["scheme", "host", "path", "fragment", "param-0", "param-1", "param-2", "param-3", "param-4"])
        #expect(output.fields.map(\.value) == ["https", "example.test", "/", "end", "1", "2", "", "", "x"])
        #expect(output.fields.last?.label == "(empty name)")
        #expect(Set(output.fields.map(\.id)).count == output.fields.count)
        #expect(output.status == "5 parameters")
        #expect(output.presentation == .fields)
        #expect(output.syntax == .json)
    }

    @Test func plusModes() throws {
        #expect(try run("inspect", "q=a+b%2Bc").primaryText == "[\n  {\"name\": \"q\", \"value\": \"a+b+c\"}\n]")
        #expect(try run("inspect", "q=a+b%2Bc", mode: "form").primaryText == "[\n  {\"name\": \"q\", \"value\": \"a b+c\"}\n]")
        #expect(try run("inspect", "a+b=%252B", mode: "form").fields.last?.label == "a b")
        #expect(try run("inspect", "a+b=%252B", mode: "form").fields.last?.value == "%2B")
    }

    @Test func ipv6AndRawComponents() throws {
        let output = try run("inspect", "https://user:pw@[::1]:8080/p/a?x=1#f")
        #expect(output.fields.map(\.label) == ["Scheme", "User info", "Host", "Port", "Path", "Fragment", "x"])
        #expect(output.fields.map(\.value) == ["https", "user:pw", "[::1]", "8080", "/p/a", "f", "1"])
        #expect(output.primaryText == "[\n  {\"name\": \"x\", \"value\": \"1\"}\n]")
        #expect(output.status == "1 parameter")
        let raw = try run("inspect", " \nAb+1.2-x://first@last@EXAMPLE:%38/a%2Fb#%ZZ \r\n")
        #expect(raw.fields.map(\.value) == ["Ab+1.2-x", "first@last", "EXAMPLE:%38", "/a%2Fb", "%ZZ"])
        #expect(try run("inspect", "x://[::1]/").fields[1].value == "[::1]")
    }

    @Test func queryDetectionAndEmptySegments() throws {
        #expect(try run("inspect", "?a=%E2%9C%93").primaryText == "[\n  {\"name\": \"a\", \"value\": \"✓\"}\n]")
        let output = try run("inspect", "https://example.test/path")
        #expect(output.primaryText == "[]")
        #expect(output.status == "No query parameters")
        #expect(output.fields.map(\.label) == ["Scheme", "Host", "Path"])
        #expect(output.fields.map(\.value) == ["https", "example.test", "/path"])
        #expect(try run("inspect", "a=1&&b=2").primaryText == "[\n  {\"name\": \"a\", \"value\": \"1\"},\n  {\"name\": \"b\", \"value\": \"2\"}\n]")
        #expect(try run("inspect", "relative/path?flag#ignored?x=2").primaryText == "[\n  {\"name\": \"flag\", \"value\": \"\"}\n]")
        #expect(try run("inspect", "a=b=c#ignore").fields.last?.value == "b=c")
        for text in ["", " \r\n ", "flag", "?", "&&&", "https://example.test/#?a=1"] {
            #expect(try run("inspect", text).primaryText == "[]")
        }
    }

    @Test func jsonEscaping() throws {
        #expect(try run("inspect", "x=\"q\"").primaryText == "[\n  {\"name\": \"x\", \"value\": \"\\\"q\\\"\"}\n]")
        #expect(try run("inspect", "x=%00%01%08%09%0A%0C%0D%1F%5C%E2%80%A8%E2%80%A9").primaryText == "[\n  {\"name\": \"x\", \"value\": \"\\u0000\\u0001\\b\\t\\n\\f\\r\\u001F\\\\\\u2028\\u2029\"}\n]")
        #expect(try run("inspect", "%22=%26%3D").primaryText == "[\n  {\"name\": \"\\\"\", \"value\": \"&=\"}\n]")
    }

    @Test func invalidPercentEscapes() throws {
        #expect(try invalid("decode", "%G0") == ToolDiagnostic("Invalid percent escape “%G0”.", at: TextLocation(line: 1, column: 1)))
        #expect(try invalid("decode", "%") == ToolDiagnostic("Invalid percent escape “%”.", at: TextLocation(line: 1, column: 1)))
        #expect(try invalid("decode", "%A").message == "Invalid percent escape “%A”.")
        #expect(try invalid("decode", "%é🙂").message == "Invalid percent escape “%é🙂”.")
        #expect(try invalid("inspect", "a=1&b=%ZZ") == ToolDiagnostic("Invalid percent escape “%ZZ”.", at: TextLocation(line: 1, column: 7)))
        #expect(try invalid("inspect", " \r\n?é=ok&b=%Z0 \n").location == TextLocation(line: 2, column: 9))
        #expect(try invalid("inspect", "?%G0=value").location == TextLocation(line: 1, column: 2))
        #expect(try invalid("inspect", "a=%&b=2").message == "Invalid percent escape “%”.")
        #expect(try invalid("decode", "é\r\nx\r%ZZ").location == TextLocation(line: 3, column: 1))
    }

    @Test func invalidUTF8() throws {
        for text in ["%FF", "%C0%80", "%ED%A0%80", "%E2%9C", "%D3N6", "%E2%41%80", "%F0%90%80%41"] {
            #expect(try invalid("decode", text) == ToolDiagnostic("Decoded bytes are not UTF-8 text."))
            #expect(try invalid("inspect", "x=" + text).message == "Decoded bytes are not UTF-8 text.")
        }
    }

    @Test func limitsAndCancellation() throws {
        for id in ["encode", "decode", "inspect"] {
            let cmd = try command(id)
            #expect(cmd.run(ToolRequest(input: .text("x=1"), cancellation: CancellationCheck { true })) == .cancelled)
            #expect(cmd.run(ToolRequest(input: .text("x=1"), limits: ToolLimits(maxOutputBytes: 1))) == .tooLarge(ToolLimits(maxOutputBytes: 1).outputLimitMessage))
            if case .needsInput = cmd.run(ToolRequest(input: .none)) {} else { Issue.record("Expected missing input") }
            let limits = ToolLimits(maxInputBytes: 2)
            #expect(cmd.run(ToolRequest(input: .text("abc"), limits: limits)) == .tooLarge(limits.inputLimitMessage))
        }
        #expect(try command("encode").run(ToolRequest(input: .text(" "), limits: ToolLimits(maxOutputBytes: 3))).output?.primaryText == "%20")
        #expect(try command("decode").run(ToolRequest(input: .text("%41"), limits: ToolLimits(maxOutputBytes: 1))).output?.primaryText == "A")
        // Query inspection produces flat output; the nesting limit does not apply.
        let limits = ToolLimits(maxNestingDepth: 1)
        #expect(try command("inspect").run(ToolRequest(input: .text("x=1"), limits: limits)).output?.primaryText == "[\n  {\"name\": \"x\", \"value\": \"1\"}\n]")
        #expect(try command("inspect").run(ToolRequest(input: .text(""), limits: limits)).output?.primaryText == "[]")
    }

    @Test func largeInput() throws {
        let text = String(repeating: "é", count: 100_000)
        let encoded = try run("encode", text).primaryText
        #expect(encoded.utf8.count == 600_000)
        #expect(try run("decode", encoded).primaryText == text)
        let many = try run("inspect", String(repeating: "a=1&", count: 10_000))
        #expect(many.fields.count == 10_000)
        #expect(many.status == "10000 parameters")
    }

    @Test func commandMetadataAndAffinity() throws {
        #expect(URLTools.commands.count == 3)
        #expect(URLTools.commands.allSatisfy { $0.group == .url })
        func profile(_ kinds: Set<InputKind>) -> InputProfile {
            InputProfile(isAttached: true, kinds: kinds, primaryKind: .text, byteCount: 0, lineCount: 1, isBlank: false)
        }
        #expect(try command("encode").affinity(InputProfile(isAttached: true, kinds: [.url, .text], primaryKind: .url, byteCount: 0, lineCount: 1, isBlank: false)) == 0)
        #expect(try command("encode").affinity(InputDetector.profile(for: "a b & c")) == 30)
        #expect(try command("encode").affinity(InputDetector.profile(for: "line one\nline two")) == 0)
        #expect(try command("decode").affinity(profile([.percentEncoded, .url])) == 90)
        #expect(try command("decode").affinity(profile([.url])) == 35)
        #expect(try command("decode").affinity(profile([])) == 0)
        #expect(try command("inspect").affinity(profile([.url, .queryString])) == 95)
        #expect(try command("inspect").affinity(profile([.queryString])) == 90)
        #expect(try command("inspect").affinity(profile([])) == 0)
        let option = try #require(command("inspect").options.first)
        #expect(option.id == "mode")
        #expect(option.label == "Plus sign")
        #expect(option.defaultValue == "uri")
        #expect(try command("inspect").copyNoun(ToolOptions()) == "parameters")
    }
}


@Suite struct URLRawQueryTests {
    private func inspect(_ text: String) throws -> ToolOutput {
        let command = try #require(URLTools.commands.first { $0.id == "url.inspect" })
        return try #require(command.run(ToolRequest(input: .text(text))).output)
    }

    @Test func questionMarksInsideRawQueryValuesAreKept() throws {
        #expect(try inspect("q=what?yes").primaryText == "[\n  {\"name\": \"q\", \"value\": \"what?yes\"}\n]")
        #expect(try inspect("path/page?a=1").primaryText == "[\n  {\"name\": \"a\", \"value\": \"1\"}\n]")
        #expect(try inspect("?a=1?b").primaryText == "[\n  {\"name\": \"a\", \"value\": \"1?b\"}\n]")
        #expect(try inspect("https://x.test/p?q=a?b").primaryText == "[\n  {\"name\": \"q\", \"value\": \"a?b\"}\n]")
    }
}

@Suite struct URLSchemeWithoutAuthorityTests {
    private func inspect(_ text: String) throws -> ToolOutput {
        let command = try #require(URLTools.commands.first { $0.id == "url.inspect" })
        return try #require(command.run(ToolRequest(input: .text(text))).output)
    }

    private func value(_ output: ToolOutput, _ id: String) -> String? {
        output.fields.first { $0.id == id }?.value
    }

    @Test func mailtoSplitsPathAndQuery() throws {
        let output = try inspect("mailto:foo=bar@example.com?subject=Hello")
        #expect(output.primaryText == "[\n  {\"name\": \"subject\", \"value\": \"Hello\"}\n]")
        #expect(value(output, "scheme") == "mailto")
        #expect(value(output, "path") == "foo=bar@example.com")
        #expect(value(output, "host") == nil)
        let plain = try inspect("mailto:dev@example.com?subject=Hello")
        #expect(value(plain, "scheme") == "mailto")
        #expect(value(plain, "path") == "dev@example.com")
    }

    @Test func dataAndFileURIsHaveNoInventedParameters() throws {
        let data = try inspect("data:text/plain;base64,SGVsbG8=")
        #expect(data.primaryText == "[]")
        #expect(value(data, "path") == "text/plain;base64,SGVsbG8=")
        let file = try inspect("file:/tmp/a=b")
        #expect(file.primaryText == "[]")
        #expect(value(file, "path") == "/tmp/a=b")
    }

    @Test func rawQueriesAndDrivePathsAreNotSchemes() throws {
        #expect(try inspect("q=a:b").primaryText == "[\n  {\"name\": \"q\", \"value\": \"a:b\"}\n]")
        #expect(value(try inspect("C:x=1"), "scheme") == nil)
    }
}
