import Foundation

/// Inspects compact JWTs without authenticating their contents.
public enum JWTTools {
    public static let commands: [ToolCommand] = [ToolCommand(
        id: "jwt.decode", title: "Decode JWT",
        summary: "Header and claims, signature unverified", group: .jwt, icon: .glyph("JWT"),
        aliases: ["inspect jwt", "jwt decoder", "jwt claims", "parse token", "bearer token", "id token", "access token"],
        copyNoun: "claims", affinity: { $0.has(.jwt) ? 100 : 0 }, evaluate: evaluate
    )]

    static func evaluate(_ request: ToolRequest) -> ToolResult {
        guard let original = request.input.text else { return .needsInput("Paste text to use Decode JWT.") }
        if request.cancellation.isCancelled { return .cancelled }
        var token = original.trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings: [String] = []
        if token.prefix(7).lowercased() == "bearer " {
            token = String(token.dropFirst(7).drop(while: { $0 == " " }))
            warnings.append("Removed the “Bearer” prefix.")
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 5 {
            return .unsupported("This is an encrypted JWT (JWE). Toolchord can’t decode it without the key.")
        }
        guard parts.count == 3 else {
            return .invalid(ToolDiagnostic("A JWT has three parts separated by dots (header.payload.signature)."))
        }
        let tokenStart = original.range(of: token)?.lowerBound ?? original.startIndex
        let headerOffset = original.utf8.distance(from: original.utf8.startIndex, to: tokenStart)
        do {
            let header = try decode(String(parts[0]), name: "header", offset: headerOffset, request: request)
            let payload = try decode(String(parts[1]), name: "payload",
                                     offset: headerOffset + parts[0].utf8.count + 1, request: request)
            warnings += header.warnings + payload.warnings
            let headerClaims = try JWTClaims.scan(header.minified, request: request)
            let claims = try JWTClaims.scan(payload.minified, request: request)
            if let alg = headerClaims.last(where: { $0.name == "alg" }), alg.value.first == "\"",
               try JSONStringCodec.unescape(alg.value, limits: request.limits, cancellation: request.cancellation) == "none" {
                warnings.append("The header says alg: none, so this token has no signature.")
            }
            var expiry = ResultField(id: "expiry", label: "Expiry", value: "No expiry claim",
                                     isCopyable: false, isMonospaced: false)
            if let exp = claims.last(where: { $0.name == "exp" }) {
                if let date = try JWTNumericDate.parse(exp.value, cancellation: request.cancellation) {
                    let expired = date.seconds <= request.now.timeIntervalSince1970
                    expiry.value = date.instant
                    expiry.note = date.relative(to: request.now.timeIntervalSince1970)
                    expiry.tone = expired ? .warning : .normal
                    if expired { warnings.append("Expiry is in the past.") }
                } else {
                    expiry.value = "exp isn’t a number"
                    expiry.tone = .warning
                }
            }
            if let nbf = claims.last(where: { $0.name == "nbf" }),
               let date = try JWTNumericDate.parse(nbf.value, cancellation: request.cancellation),
               date.seconds > request.now.timeIntervalSince1970 {
                warnings.append("This token is not valid yet (nbf is in the future).")
            }
            // Expiry first: it is the field people look for most.
            var fields = [expiry, ResultField(id: "header", label: "Header", value: header.formatted)]
            for (index, claim) in claims.enumerated() {
                if index % 1024 == 0, request.cancellation.isCancelled { return .cancelled }
                var note: String?
                var tone = ResultField.Tone.normal
                if ["exp", "iat", "nbf"].contains(claim.name) {
                    if let date = try JWTNumericDate.parse(claim.value, cancellation: request.cancellation) {
                        note = date.instant
                    } else {
                        note = "Not a NumericDate (seconds since 1970)"
                        tone = .warning
                    }
                }
                fields.append(ResultField(id: "claim-\(index)", label: claim.name, value: claim.value, note: note, tone: tone))
            }
            return .success(ToolOutput(primaryText: payload.formatted, status: "Signature unverified",
                                       presentation: .text, syntax: .json, fields: fields, warnings: warnings,
                                       statusTone: .warning))
        } catch let failure as JWTFailure {
            return failure.result
        } catch let failure as JSONText.Failure {
            switch failure {
            case .cancelled: return .cancelled
            case .tooLarge(let message): return .tooLarge(message)
            case .invalid(let diagnostic): return .invalid(ToolDiagnostic(diagnostic.message))
            }
        } catch { return .invalid(ToolDiagnostic("Unable to decode the JWT.")) }
    }

    struct Document {
        var formatted: String
        var minified: String
        var warnings: [String]
    }

    static func decode(_ segment: String, name: String, offset: Int, request: ToolRequest) throws -> Document {
        guard !segment.isEmpty else {
            let location = TextLocator.location(ofUTF8Offset: offset, in: request.input.text ?? "")
            throw JWTFailure(.invalid(ToolDiagnostic("The \(name) must not be empty.", at: location)))
        }
        let bytes: [UInt8]
        do {
            bytes = try Base64Codec.decode(segment, alphabet: .url, ignoreWhitespace: false, surroundingWhitespace: .reject,
                                           maxOutputBytes: request.limits.maxOutputBytes, cancellation: request.cancellation)
        } catch Base64Codec.ProcessingError.invalid(let failure) {
            // Codec offsets refer directly to a segment of the original input.
            let original = request.input.text ?? ""
            let location = failure.offset.map { TextLocator.location(ofUTF8Offset: offset + $0, in: original) }
            throw JWTFailure(.invalid(ToolDiagnostic("The \(name) isn’t valid Base64URL: \(failure.message)", at: location)))
        } catch Base64Codec.ProcessingError.cancelled { throw JWTFailure(.cancelled) }
        catch Base64Codec.ProcessingError.tooLarge { throw JWTFailure(.tooLarge(request.limits.outputLimitMessage)) }
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw JWTFailure(.invalid(ToolDiagnostic("The \(name) isn’t UTF-8 text.")))
        }
        func process(_ style: JSONText.Style) throws -> JSONText.Processed {
            switch JSONText.process(text, style: style, limits: request.limits, cancellation: request.cancellation) {
            case .success(let value): return value
            case .failure(.invalid(let diagnostic)):
                throw JWTFailure(.invalid(ToolDiagnostic("The \(name) isn’t valid JSON: \(diagnostic.message)")))
            case .failure(let failure): throw failure
            }
        }
        let formatted = try process(.indented("  "))
        guard formatted.rootKind == .object else {
            throw JWTFailure(.invalid(ToolDiagnostic(name == "header" ? "The header must be a JSON object." : "The claims must be a JSON object.")))
        }
        return Document(formatted: formatted.text, minified: try process(.minified).text, warnings: formatted.warnings)
    }
}

struct JWTFailure: Error { let result: ToolResult; init(_ result: ToolResult) { self.result = result } }
