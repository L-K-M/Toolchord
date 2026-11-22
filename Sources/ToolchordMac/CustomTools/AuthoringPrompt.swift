import Foundation
import ToolchordCore

enum AuthoringPrompt {
    static func request(description: String, current: ScriptToolDefinition, isNew: Bool) throws -> String {
        let context: String
        if isNew {
            context = "Create a new tool. Start with empty options and actions unless requested."
        } else {
            // Present editable code verbatim and omit the opaque document ID.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let controls = String(decoding: try encoder.encode(current.options ?? []), as: UTF8.self)
            let actions = String(decoding: try encoder.encode(current.actions), as: UTF8.self)
            context = """
            Revise the existing JavaScript below to implement the request. The new preview still
            receives the original input, not the previous result. Make the smallest change that
            fulfills the request. Preserve controls unless asked to change them.
            Title: \(current.title)
            Purpose: \(current.summary)
            Options: \(controls)
            Actions: \(actions)
            Regenerate button: \(current.regenerateTitle ?? "none")
            Existing JavaScript:
            \(current.source)
            """
        }
        return "\(context)\n\nUser request:\n\(description)"
    }

    static let instructions = """
    Implement the requested tool in synchronous JavaScriptCore. The host wraps your JavaScript
    statements in functions. Supply function bodies only, without tests or calls at global scope.
    No imports, Node, DOM, Web Crypto, fetch, promises, or file access. Use the host methods below.
    Inside previewBody, input is the entire input string, including spaces. Return the transformed
    string directly, or return {primaryText, status, fields: [{id,label,value}]}. For example,
    the previewBody of an uppercase tool is just: return input.toUpperCase();
    For malformed input, throw Error with a helpful message. A preview cannot perform side effects.

    These are the host's JavaScript calls (arguments in order):
    api.native("crypto.digest", algorithm, input) returns a lowercase hex string; algorithm is
    "md5", "sha1", "sha256", or "sha512". api.native("crypto.hkdfHex", hexKey, context, byteCount)
    derives key material. api.native("text.transliterate", input) transliterates text.
    api.native("text.byteCountLabel", input) formats its UTF-8 size.
    api.native("text.numericType", character) returns "decimal", "digit", "numeric" or "".
    api.native("text.graphemeClasses", input) returns one marker per grapheme: W for whitespace, O otherwise.
    api.native("text.compare", a, b, caseSensitive) returns -1, 0 or 1 with numeric ordering.
    api.native("clock.offsetSeconds", unixMilliseconds) returns the local zone offset in seconds.
    api.native("markdown.parse", input) returns a flat tree {nodes} or an error object.

    Most tools have options=[] and actions=[]. Add controls only when requested.
    In metadata, a toggle uses {id,label,defaultValue:"false",choices:[]}. A choice uses
    {id,label,defaultValue,choices:[{id,label}]}. Inside JavaScript, options[id] is a string.
    Only declare actions for requested buttons. Their performBody calls api.clipboard.writeText(text)
    exactly once per action. Normal result copying is built in. Optional helpers can be shared
    between preview and actions.

    Set isGenerator=false and regenerateTitle="" for any tool that takes input.
    For a tool that generates values without input, set isGenerator=true with a regenerateTitle.
    api.now is Unix milliseconds and api.seed is stable until Regenerate. Use these instead of Date.now
    and Math.random. A generator can supply a makeSeedBody to derive a string
    seed from api.entropy, an array of random bytes. Preserve existing controls on revisions.
    """
}
