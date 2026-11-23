import Foundation
import JavaScriptCore

/// Built-ins and user programs use the same interpreter and host interface.
/// The caller chooses the execution process, never the tool document.
enum ScriptRuntime {
    static let wireLimit = 40 * 1024 * 1024

    static func evaluate(id: String, source: String, request: ToolRequest, action: String? = nil, requiresActionHandler: Bool = false) throws -> Data {
        guard !request.cancellation.isCancelled else { throw CancellationError() }
        guard let context = JSContext() else { throw ScriptFailure("Could not start JavaScript.") }
        // Each invocation gets fresh globals. Keep all bridges local to this
        // context and release their captured request when evaluation ends.
        let cancelled: @convention(block) () -> Bool = { request.cancellation.isCancelled }
        let native: @convention(block) (String, JSValue) -> JSValue? = { name, arguments in
            guard let current = JSContext.current() else { return nil }
            do {
                guard let values = arguments.toArray(), values.count <= 12 else { throw ScriptFailure("Invalid host arguments.") }
                guard let value = try ScriptNative.call(name, values, request) else { throw ScriptFailure("Unknown host operation: " + name) }
                return JSValue(object: value, in: current)
            } catch {
                current.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: current)
                return nil
            }
        }
        context.setObject(cancelled, forKeyedSubscript: "__cancelled" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
        let metadata: [String: Any] = [
            "id": id, "seed": request.seed as Any? ?? NSNull(),
            "now": request.now.timeIntervalSince1970 * 1000, "timeZone": request.timeZone.identifier,
            "limits": ["maxInputBytes": request.limits.maxInputBytes, "maxOutputBytes": request.limits.maxOutputBytes,
                       "maxNestingDepth": request.limits.maxNestingDepth, "outputLimitMessage": request.limits.outputLimitMessage,
                       "nestingLimitMessage": request.limits.nestingLimitMessage] as [String: Any]
        ]
        // Capture intrinsics before user code runs. Clipboard writes are only
        // intents; the host commits a successful action after revision checks.
        let invoke = context.evaluateScript("""
          ((native, cancelled, encode) => (fn, input, options, meta, action) => {
              const api = Object.assign(meta, { native: (name, ...args) => native(name, args), cancelled });
              let write, sensitivity = "normal";
              if (action !== null) {
                  api.clipboard = { writeText(text, policy = "normal") {
                      if (typeof text !== 'string' || write !== undefined)
                          throw new Error('An action must write one text value.');
                      if (policy !== 'normal' && policy !== 'secret') throw new Error('Unknown clipboard policy.');
                      write = text;
                      sensitivity = policy;
                  }};
                  fn(action, input, options, api);
                  if (write === undefined) throw new Error('The action did not write any text.');
                  return encode({ primaryText: write, status: 'Ready to copy', sensitivity });
              }
              const result = fn(input, options, api);
              if (typeof result === 'string') return encode({ primaryText: result, status: 'Ready' });
              return encode(result);
          })(__native, __cancelled, JSON.stringify)
          """)
        context.evaluateScript(source)
        try check(context)
        if requiresActionHandler, context.evaluateScript("typeof perform === 'function'")?.toBool() != true {
            throw ScriptFailure("Declare function perform(action, input, options, api) for the requested actions.")
        }
        let function = context.objectForKeyedSubscript(action == nil ? "preview" : "perform")
        guard let function, function.isObject else {
            throw ScriptFailure(action == nil ? "Define function preview(input, options, api)." : "Define function perform(action, input, options, api).")
        }
        let value = invoke?.call(withArguments: [function, request.input.text as Any? ?? NSNull(),
                                                 request.options.values, metadata, action as Any? ?? NSNull()])
        try check(context)
        guard let value, value.isString, let string = value.toString() else { throw ScriptFailure("Return text or a tool result.") }
        guard string.utf8.count <= wireLimit else { throw ScriptFailure(request.limits.outputLimitMessage) }
        return Data(string.utf8)
    }

    static func randomEntropy() -> [UInt8] {
        (0..<512).map { _ in UInt8.random(in: .min ... .max) }
    }

    static func seed(id: String, source: String, context: SeedContext, entropy: [UInt8] = randomEntropy()) throws -> String {
        guard let js = JSContext() else { throw ScriptFailure("Could not start JavaScript.") }
        js.evaluateScript(source)
        try check(js)
        let api: [String: Any] = ["id": id, "now": Int64(exactly: (context.now.timeIntervalSince1970 * 1000).rounded(.down)) as Any? ?? NSNull(), "entropy": entropy]
        guard let makeSeed = js.objectForKeyedSubscript("makeSeed"), !makeSeed.isUndefined else {
            return entropy.prefix(32).map { String(format: "%02x", $0) }.joined()
        }
        let value = makeSeed.call(withArguments: [context.options.values, api])
        try check(js)
        guard let value, value.isString, let seed = value.toString() else { throw ScriptFailure("Invalid generator seed.") }
        return seed
    }

    private static func check(_ context: JSContext) throws {
        if let exception = context.exception {
            throw ScriptFailure(String((exception.toString() ?? "JavaScript error").prefix(500)))
        }
    }

    static func result(_ data: Data, limits: ToolLimits) throws -> ToolResult {
        let value = try JSONDecoder().decode(Response.self, from: data)
        if let kind = value.error {
            if kind == "cancelled" { return .cancelled }
            guard let message = value.message, !message.isEmpty else { throw ScriptFailure("A tool error needs a message.") }
            switch kind {
            case "needsInput": return .needsInput(message)
            case "tooLarge": return .tooLarge(message)
            case "invalid": return .invalid(ToolDiagnostic(message, at: value.location.map { TextLocation(line: max(1,$0.line), column: max(1,$0.column)) }))
            case "unsupported": return .unsupported(message)
            default: throw ScriptFailure("Unknown tool error kind.")
            }
        }
        guard let primary = value.primaryText else { throw ScriptFailure("Return text or an object with primaryText.") }
        let fields = value.fields ?? []
        guard primary.utf8.count <= limits.maxOutputBytes, fields.allSatisfy({ $0.value.utf8.count <= limits.maxOutputBytes }) else {
            return .tooLarge(limits.outputLimitMessage)
        }
        guard Set(fields.map(\.id)).count == fields.count else { throw ScriptFailure("Field identifiers must be unique.") }
        let output = ToolOutput(primaryText: primary, status: value.status ?? "Ready",
                                presentation: value.presentation == "fields" ? .fields : .text,
                                syntax: value.syntax == "json" ? .json : value.syntax == "xml" ? .xml : .plain,
                                fields: fields.map(\.result), warnings: value.warnings ?? [],
                                swatch: value.swatch.map { .init(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha ?? 1) },
                                statusTone: value.statusTone == "warning" ? .warning : .success,
                                sensitivity: value.sensitivity == "secret" ? .secret : .normal)
        return .success(output)
    }

    /// Strip unknown properties and bound display metadata in the disposable
    /// worker before the app receives a user program's result.
    static func checkedUserResponse(_ bytes: Data) throws -> Data {
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        let fields = response.fields ?? [], warnings = response.warnings ?? []
        guard fields.count <= 256, warnings.count <= 128,
              (response.status?.utf8.count ?? 0) <= 4096,
              (response.message?.utf8.count ?? 0) <= 4096,
              warnings.allSatisfy({ $0.utf8.count <= 4096 }),
              fields.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 && $0.label.utf8.count <= 1024 && ($0.note?.utf8.count ?? 0) <= 4096 })
        else { throw ScriptFailure("The tool returned too many fields or too much display text.") }
        guard accepts(response.sensitivity, ["normal","secret"]),
              accepts(response.syntax, ["plain","json","xml"]),
              accepts(response.statusTone, ["success","warning"]),
              accepts(response.presentation, ["text","fields"]),
              fields.allSatisfy({ accepts($0.tone, ["normal","success","warning"]) })
        else { throw ScriptFailure("The result uses an unknown presentation or clipboard setting.") }
        if let swatch = response.swatch, ![swatch.red, swatch.green, swatch.blue, swatch.alpha ?? 1].allSatisfy({ (0...1).contains($0) }) {
            throw ScriptFailure("Color components must be between zero and one.")
        }
        return try JSONEncoder().encode(response)
    }

    private static func accepts(_ value: String?, _ allowed: [String]) -> Bool {
        value.map(allowed.contains) ?? true
    }

    private struct Response: Codable {
        struct Location: Codable { let line, column: Int }
        struct Swatch: Codable { let red, green, blue: Double; let alpha: Double? }
        struct Field: Codable {
            let id, label, value: String
            let note, tone: String?
            let isCopyable, isMonospaced: Bool?
            var result: ResultField {
                ResultField(id: id, label: label, value: value, note: note,
                            tone: tone == "warning" ? .warning : tone == "success" ? .success : .normal,
                            isCopyable: isCopyable ?? true, isMonospaced: isMonospaced ?? true)
            }
        }
        let error, message, primaryText, status, presentation, syntax, sensitivity, statusTone: String?
        let location: Location?
        let fields: [Field]?
        let warnings: [String]?
        let swatch: Swatch?
    }
}
