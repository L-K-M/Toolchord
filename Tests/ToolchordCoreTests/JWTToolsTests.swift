import Foundation
import Testing
@testable import ToolchordCore

@Suite struct JWTToolsTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func command() throws -> ToolCommand { try #require(JWTTools.commands.first { $0.id == "jwt.decode" }) }

    func token(_ payload: String, header: String = "{\"alg\":\"HS256\"}", signature: String = "") -> String {
        Base64Codec.encode(Array(header.utf8), alphabet: .url) + "." +
        Base64Codec.encode(Array(payload.utf8), alphabet: .url) + "." + signature
    }

    func run(_ text: String, limits: ToolLimits = .standard, cancellation: CancellationCheck = .never) throws -> ToolResult {
        try command().run(ToolRequest(input: .text(text), now: now, timeZone: TimeZone(secondsFromGMT: 0)!,
                                      limits: limits, cancellation: cancellation))
    }

    func output(_ text: String) throws -> ToolOutput { try #require(run(text).output) }
    func field(_ output: ToolOutput, _ id: String) throws -> ResultField { try #require(output.fields.first { $0.id == id }) }

    @Test func unsignedFixture() throws {
        let result = try output("eyJhbGciOiJub25lIn0.eyJleHAiOjAsInN1YiI6IngifQ.")
        #expect(result.primaryText == "{\n  \"exp\": 0,\n  \"sub\": \"x\"\n}")
        #expect(result.status == "Signature unverified")
        #expect(result.syntax == .json)
        #expect(result.presentation == .text)
        #expect(result.warnings == ["The header says alg: none, so this token has no signature.", "Expiry is in the past."])
        let expiry = try field(result, "expiry")
        #expect(expiry.value == "1970-01-01T00:00:00.000Z")
        #expect(expiry.tone == .warning)
        #expect(!expiry.isCopyable && !expiry.isMonospaced)
        #expect(result.fields.map(\.id) == ["expiry", "header", "claim-0", "claim-1"])
        #expect(result.statusTone == .warning)
        #expect(try field(result, "claim-0").label == "exp")
        #expect(try field(result, "claim-0").value == "0")
        #expect(try field(result, "claim-0").note == "1970-01-01T00:00:00.000Z")
        #expect(try field(result, "claim-1").value == "\"x\"")
    }

    @Test func signedAndBearerFixtures() throws {
        let jwt = token("{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"iat\":1516239022}",
                        header: "{\"alg\":\"HS256\",\"typ\":\"JWT\"}",
                        signature: "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")
        let result = try output(jwt)
        #expect(result.primaryText == "{\n  \"sub\": \"1234567890\",\n  \"name\": \"John Doe\",\n  \"iat\": 1516239022\n}")
        #expect(try field(result, "header").value == "{\n  \"alg\": \"HS256\",\n  \"typ\": \"JWT\"\n}")
        #expect(try field(result, "expiry").value == "No expiry claim")
        #expect(try field(result, "claim-2").note == "2018-01-18T01:30:22.000Z")
        for prefix in ["Bearer ", "  bEaReR    "] {
            var expected = result
            expected.warnings = ["Removed the “Bearer” prefix."]
            #expect(try output(prefix + jwt + "\r\n") == expected)
        }
    }

    @Test func dateFixtures() throws {
        let future = try output(token("{\"exp\":1700003600}"))
        #expect(try field(future, "expiry").note == "Expires in 1 hour")
        #expect(future.warnings.isEmpty)
        let wrongType = try output(token("{\"exp\":\"soon\"}"))
        #expect(try field(wrongType, "expiry").value == "exp isn’t a number")
        #expect(try field(wrongType, "expiry").tone == .warning)
        let exponent = try output(token("{\"exp\":1.7e9}"))
        #expect(try field(exponent, "expiry").value == "2023-11-14T22:13:20.000Z")
        #expect(exponent.warnings == ["Expiry is in the past."])
        #expect(try output(token("{\"nbf\":1700003600}")).warnings == ["This token is not valid yet (nbf is in the future)."])
    }

    @Test func preservesSpellingAndOrder() throws {
        let result = try output(token(#"{"n":9007199254740993,"o":{"a":[1, 2]},"\u0061":"x\n\"y","n":-0.0e+2}"#))
        #expect(try field(result, "claim-0").value == "9007199254740993")
        #expect(try field(result, "claim-1").value == "{\"a\":[1,2]}")
        #expect(try field(result, "claim-2").label == "a")
        #expect(try field(result, "claim-2").value == #""x\n\"y""#)
        #expect(try field(result, "claim-3").value == "-0.0e+2")
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].hasPrefix("Duplicate member name “n”"))
        let escapedAlg = try output(token("{}", header: #"{"alg":"n\u006fne"}"#))
        #expect(escapedAlg.warnings == ["The header says alg: none, so this token has no signature."])
    }

    @Test func malformedFixtures() throws {
        #expect(try run("a.b.c.d.e") == .unsupported("This is an encrypted JWT (JWE). Toolchord can’t decode it without the key."))
        for text in ["abc.def", "", "   ", "a.b.c.d", "a"] {
            #expect(try run(text) == .invalid(ToolDiagnostic("A JWT has three parts separated by dots (header.payload.signature).")))
        }
        for (text, message) in [
            ("!!!.eyJ9.", "The header isn’t valid Base64URL:"),
            (token("{}", header: "[1]"), "The header must be a JSON object."),
            (token("{\"a\":}"), "The payload isn’t valid JSON:"),
            (token("[]"), "The claims must be a JSON object."),
            (token("{}", header: "{"), "The header isn’t valid JSON:"),
            (".e30.", "The header must not be empty."),
            ("e30..", "The payload must not be empty."),
            ("e30.!!!.", "The payload isn’t valid Base64URL:"),
            ("_w.e30.", "The header isn’t UTF-8 text."),
            ("e30._w.", "The payload isn’t UTF-8 text.")
        ] {
            let result = try run(text)
            guard case .invalid(let diagnostic) = result else { Issue.record("Expected invalid: \(result)"); continue }
            #expect(diagnostic.message.hasPrefix(message))
            if message.contains("JSON:") { #expect(diagnostic.location == nil) }
        }
        guard case .invalid(let diagnostic) = try run(" \r\nBearer e30.!!!.") else { Issue.record("Expected invalid"); return }
        #expect(diagnostic.location == TextLocation(line: 2, column: 12))
    }

    @Test func millisecondPrecisionAndRange() throws {
        let cases: [(String, String)] = [
            ("-0.0001", "1969-12-31T23:59:59.999Z"),
            ("0.99999999999999999999", "1970-01-01T00:00:00.999Z"),
            ("1700000000.12399999", "2023-11-14T22:13:20.123Z"),
            ("-62135596800", "0001-01-01T00:00:00.000Z"),
            ("-62135596800.0001", "Outside the supported date range"),
            ("253402300799.9999", "9999-12-31T23:59:59.999Z"),
            ("253402300800", "Outside the supported date range"),
            ("1e99999999999999999999", "Outside the supported date range"),
            ("-1e-99999999999999", "1969-12-31T23:59:59.999Z"),
            ("0e99999999", "1970-01-01T00:00:00.000Z"),
            ("170000000012399999e-8", "2023-11-14T22:13:20.123Z")
        ]
        for (number, expected) in cases {
            let result = try output(token("{\"exp\":\(number),\"iat\":\(number)}"))
            #expect(try field(result, "expiry").value == expected)
            #expect(try field(result, "claim-1").note == expected)
        }
    }

    @Test func relativeWording() throws {
        let cases: [(Double, String)] = [
            (0, "now"), (0.5, "now"), (-0.5, "now"), (1, "Expires in 1 second"),
            (-1, "Expired 1 second ago"), (300, "Expires in 5 minutes"),
            (7200, "Expires in 2 hours"), (-86400, "Expired 1 day ago"),
            (-259200, "Expired 3 days ago"), (2592000, "Expires in 1 month"),
            (31536000, "Expires in 1 year")
        ]
        for (offset, expected) in cases {
            let result = try output(token("{\"exp\":\(now.timeIntervalSince1970 + offset)}"))
            #expect(try field(result, "expiry").note == expected)
        }
    }

    @Test func limitsCancellationAndEmptyObject() throws {
        #expect(try output(token("{}")).primaryText == "{}")
        let cmd = try command()
        guard case .needsInput = cmd.run(ToolRequest(input: .none)) else { Issue.record("Expected needsInput"); return }
        #expect(try run(token("{}"), cancellation: CancellationCheck { true }) == .cancelled)
        let outputLimits = ToolLimits(maxOutputBytes: 12)
        #expect(try run(token("{\"a\":123456789}"), limits: outputLimits) == .tooLarge(outputLimits.outputLimitMessage))
        let depthLimits = ToolLimits(maxNestingDepth: 2)
        #expect(try run(token("{\"a\":[[]]}"), limits: depthLimits) == .tooLarge(depthLimits.nestingLimitMessage))
        let inputLimits = ToolLimits(maxInputBytes: 4)
        #expect(try run(token("{}"), limits: inputLimits) == .tooLarge(inputLimits.inputLimitMessage))
        let padded = "e30=.e30=."
        #expect(try output(padded).primaryText == "{}")
        let many = "{\"items\":[" + Array(repeating: "0", count: 30_000).joined(separator: ",") + "]}"
        #expect(try output(token(many)).fields.last?.value.utf8.count == 60_001)
    }

    @Test func metadata() throws {
        let cmd = try command()
        #expect(cmd.group == .jwt)
        #expect(cmd.title == "Decode JWT")
        #expect(cmd.summary == "Header and claims, signature unverified")
        #expect(cmd.icon == .glyph("JWT"))
        #expect(cmd.options.isEmpty)
        #expect(cmd.copyNoun(ToolOptions()) == "claims")
        #expect(cmd.affinity(InputProfile(isAttached: true, kinds: [.jwt], primaryKind: .jwt, byteCount: 1, lineCount: 1, isBlank: false)) == 100)
        #expect(cmd.affinity(.none) == 0)
    }

    @Test func whitespaceBesideADotIsRejected() throws {
        // Only the Base64 commands skip whitespace around their input. In a
        // compact JWT, whitespace beside a dot belongs to no segment.
        let fixtures = [
            ("eyJhbGciOiJub25lIn0. eyJleHAiOjAsInN1YiI6IngifQ.", 21),
            ("eyJhbGciOiJub25lIn0 .eyJleHAiOjAsInN1YiI6IngifQ.", 20),
        ]
        for (input, column) in fixtures {
            guard case .invalid(let diagnostic) = try run(input) else {
                Issue.record("Decoded \(input)")
                continue
            }
            #expect(diagnostic.message.contains("whitespace"), "\(diagnostic)")
            #expect(diagnostic.location == TextLocation(line: 1, column: column), "\(diagnostic)")
        }
    }
}

@Suite struct JWTNumericDateRobustnessTests {
    @Test(arguments: ["1e400", "-1e400", "1e-400", "99999999999999999999999999999", "-0", "0.0000000001", "1E+3", "253402300800", "-62135596801", "1.5e9"])
    func extremeExpiryValuesNeverCrash(_ exp: String) throws {
        let header = Base64Codec.encode(Array(#"{"alg":"none"}"#.utf8), alphabet: .url)
        let payload = Base64Codec.encode(Array("{\"exp\":\(exp),\"iat\":\(exp),\"nbf\":\(exp)}".utf8), alphabet: .url)
        let command = try #require(JWTTools.commands.first)
        let result = command.run(ToolRequest(input: .text("\(header).\(payload)."), now: Date(timeIntervalSince1970: 1_700_000_000)))
        let output = try #require(result.output, "\(exp): \(result)")
        #expect(output.fields.first { $0.id == "expiry" } != nil)
    }
}
