import Foundation

public enum Base64Tools {
    public static let commands: [ToolCommand] = [
        command(id: "base64.encode", title: "Encode Base64", summary: "Standard alphabet with padding",
                aliases: ["base64 encode", "b64 encode", "to base64", "encode b64"], alphabet: .standard, decoding: false),
        command(id: "base64.decode", title: "Decode Base64", summary: "Standard alphabet to UTF-8 text",
                aliases: ["base64 decode", "b64 decode", "from base64", "decode b64"], alphabet: .standard, decoding: true),
        command(id: "base64url.encode", title: "Encode Base64URL", summary: "URL-safe alphabet, no padding",
                aliases: ["base64url encode", "url safe base64", "base64 url encode"], alphabet: .url, decoding: false),
        command(id: "base64url.decode", title: "Decode Base64URL", summary: "URL-safe alphabet to UTF-8 text",
                aliases: ["base64url decode", "url safe base64 decode", "base64 url decode"], alphabet: .url, decoding: true),
    ]

    static func command(id: String, title: String, summary: String, aliases: [String],
                        alphabet: Base64Codec.Alphabet, decoding: Bool) -> ToolCommand {
        ToolCommand(id: id, title: title, summary: summary, group: .base64, icon: .glyph("64"), aliases: aliases,
                    options: decoding ? [.toggle("ignoreWhitespace", "Ignore whitespace", default: false)] : [],
                    copyNoun: decoding ? "decoded text" : "encoded text",
                    affinity: { profile in
                        if decoding { return profile.has(alphabet == .standard ? .base64 : .base64URL) ? 95 : 0 }
                        return alphabet == .standard && profile.isPlainText ? 31 : 0
                    },
                    evaluate: { evaluate($0, alphabet: alphabet, decoding: decoding) })
    }

    static func evaluate(_ request: ToolRequest, alphabet: Base64Codec.Alphabet, decoding: Bool) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to convert.") }
        if request.cancellation.isCancelled { return .cancelled }
        do {
            if decoding {
                let bytes = try Base64Codec.decode(text, alphabet: alphabet,
                    ignoreWhitespace: request.options.flag("ignoreWhitespace"),
                    surroundingWhitespace: .ignore,
                    maxOutputBytes: request.limits.maxOutputBytes, cancellation: request.cancellation)
                guard let decoded = String(bytes: bytes, encoding: .utf8) else {
                    return .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text."))
                }
                return .success(ToolOutput(primaryText: decoded, status: "Decoded · \(ByteCountText.string(bytes.count))"))
            }
            let encoded = try Base64Codec.encode(text.utf8, alphabet: alphabet,
                maxOutputBytes: request.limits.maxOutputBytes, cancellation: request.cancellation)
            return .success(ToolOutput(primaryText: encoded, status: alphabet == .standard ? "Base64" : "Base64URL"))
        } catch Base64Codec.ProcessingError.invalid(let failure) {
            return .invalid(ToolDiagnostic(failure.message, at: failure.offset.map {
                TextLocator.location(ofUTF8Offset: $0, in: text)
            }))
        } catch Base64Codec.ProcessingError.tooLarge {
            return .tooLarge(request.limits.outputLimitMessage)
        } catch {
            return .cancelled
        }
    }
}
