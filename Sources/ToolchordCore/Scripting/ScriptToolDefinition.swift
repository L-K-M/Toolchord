import Foundation
import JavaScriptCore

public struct ScriptToolAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

struct ScriptFailure: LocalizedError {
    var errorDescription: String? { message }
    let message: String
    init(_ message: String) { self.message = message }
}

/// A saved tool contains code and metadata only. Trial inputs and results
/// belong to the current editor session.
public struct ScriptToolDefinition: Codable, Sendable, Hashable, Identifiable {
    public var apiVersion = 1
    public var id: String
    public var title: String
    public var summary: String
    public var source: String
    public var actions: [ScriptToolAction]
    public var regenerateTitle: String?
    public var options: [ScriptOption]?
    public var capabilities: [String]
    public var palette: ScriptPalette?

    public init(id: String, title: String, summary: String = "", source: String,
                actions: [ScriptToolAction] = [], capabilities: [String] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.actions = actions
        self.capabilities = capabilities
    }

    /// Checks the header without parsing or executing JavaScript.
    public func validateMetadata() throws {
        guard Self.isValidToolID(id) else {
            throw ScriptFailure("Use a built-in tool identifier or a valid custom. identifier.")
        }
        try validateHeaderFields()
    }

    // Loading signed resources establishes the allowlist used by validateMetadata().
    private func validateHeaderFields() throws {
        guard apiVersion == 1 else { throw ScriptFailure("This tool needs an unsupported API version.") }
        try palette?.validate()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 100,
              summary.count <= 500 else { throw ScriptFailure("Give the tool a short title and description.") }
        guard Set(capabilities).isSubset(of: ["clipboard.write"]), Set(capabilities).count == capabilities.count else {
            throw ScriptFailure("Unrecognized or duplicate tool capability.")
        }
        guard actions.count <= 8, Set(actions.map(\.id)).count == actions.count,
              actions.allSatisfy({ Self.isIdentifier($0.id) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 80 }) else {
            throw ScriptFailure("Use up to eight actions with unique identifiers and short titles.")
        }
        if !actions.isEmpty && !capabilities.contains("clipboard.write") {
            throw ScriptFailure("Clipboard actions require the clipboard.write capability.")
        }
        if let label = regenerateTitle, label.isEmpty || label.count > 80 {
            throw ScriptFailure("Give the regenerate action a short label.")
        }
        let declaredOptions = options ?? []
        guard declaredOptions.count <= 16, Set(declaredOptions.map(\.id)).count == declaredOptions.count else {
            throw ScriptFailure("Choose up to 16 uniquely named options.")
        }
        for option in declaredOptions { _ = try option.toolOption() }
    }

    public func validate() throws {
        try validateMetadata()
        guard !source.isEmpty, source.utf8.count <= 128 * 1024 else {
            throw ScriptFailure("Enter JavaScript source of up to 128 KiB.")
        }
        // Parse without executing any tool code in the application process.
        guard let context = JSGlobalContextCreate(nil), let script = JSStringCreateWithCFString(source as CFString) else {
            throw ScriptFailure("The JavaScript parser is unavailable.")
        }
        defer { JSGlobalContextRelease(context); JSStringRelease(script) }
        var exception: JSValueRef?
        if !JSCheckScriptSyntax(context, script, nil, 1, &exception) {
            if let exception, let message = JSValueToStringCopy(context, exception, nil) {
                defer { JSStringRelease(message) }
                throw ScriptFailure(JSStringCopyCFString(nil, message) as String)
            }
            throw ScriptFailure("Check the JavaScript syntax.")
        }
    }

    /// Only exact shipped tool IDs and single, path-safe custom names may identify a document.
    public static func isValidToolID(_ id: String) -> Bool {
        if id.hasPrefix("custom.") { return isIdentifier(String(id.dropFirst(7))) }
        return ToolCatalog.command(id: id)?.id.hasSameUTF8(as: id) == true
    }

    private static func isIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 80 && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    public func command() throws -> ToolCommand {
        try validate()
        // Older overrides used the bundled command's search and presentation metadata.
        let presentation = palette ?? ToolCatalog.bundledDefinitions.first { $0.id == id }?.palette ?? ScriptPalette()
        return try makeCommand(presentation: presentation, execution: .worker)
    }

    /// Called only while loading the app bundle, never for a local definition with a matching ID.
    func bundledCommand() throws -> ToolCommand {
        try validateHeaderFields()
        return try makeCommand(presentation: palette ?? ScriptPalette(), execution: .bundled)
    }

    private enum Execution { case bundled, worker }

    private func makeCommand(presentation: ScriptPalette, execution: Execution) throws -> ToolCommand {
        let seed: (@Sendable (SeedContext) -> String)?
        if regenerateTitle == nil {
            seed = nil
        } else {
            switch execution {
            case .bundled: seed = { (try? ScriptRuntime.seed(id: id, source: source, context: $0)) ?? "" }
            case .worker: seed = { ScriptWorker.captureSeed($0) }
            }
        }
        @Sendable func run(_ request: ToolRequest, action: String? = nil) -> ToolResult {
            switch execution {
            case .bundled:
                do {
                    let bytes = try ScriptRuntime.evaluate(id: id, source: source, request: request, action: action,
                                                           requiresActionHandler: !actions.isEmpty)
                    if request.cancellation.isCancelled { return .cancelled }
                    return try ScriptRuntime.result(bytes, limits: request.limits)
                } catch is CancellationError { return .cancelled }
                catch { return .invalid(ToolDiagnostic(error.localizedDescription)) }
            case .worker:
                return ScriptWorker.run(id: id, source: source, request: request, action: action,
                                        requiresActionHandler: !actions.isEmpty)
            }
        }
        var command = try ToolCommand(
            id: id, title: title, summary: summary, group: presentation.toolGroup, icon: presentation.icon,
            aliases: presentation.aliases ?? [], input: regenerateTitle == nil ? .text : .none,
            options: (options ?? []).map { try $0.toolOption() }, copyNoun: presentation.copyNoun(for:),
            affinity: presentation.affinity(for:), makeSeed: seed, regenerateTitle: regenerateTitle,
            evaluate: { run($0) }
        )
        command.scriptActions = actions
        command.scriptActionHandler = { action, request in
            guard capabilities.contains("clipboard.write"), actions.contains(where: { $0.id == action }) else {
                return .unsupported("This tool has no such clipboard action.")
            }
            return run(request, action: action)
        }
        return command
    }
}
