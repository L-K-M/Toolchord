import Foundation

enum BundledScripts {
    private struct Catalog: Decodable {
        var apiVersion: Int
        var libraries: [String: [String]]
        var commands: [Entry]
    }

    struct Entry: Decodable, Sendable {
        let id, title, summary, script, group, groupTitle, copyNoun: String
        let aliases: [String]
        let symbol, glyph, regenerateTitle: String?
        let options: [ScriptOption]?
        let suggestions: [Suggestion]?
        let copyLabels: [String: [String: String]]?

        struct Suggestion: Decodable, Sendable {
            let when: [String]
            let score: Int

            func matches(_ profile: InputProfile) -> Bool {
                when.allSatisfy { condition in
                    let negative = condition.hasPrefix("!")
                    let kind = negative ? String(condition.dropFirst()) : condition
                    let matches = kind == "plain" ? profile.isPlainText : InputKind(rawValue: kind).map(profile.has) == true
                    return negative ? !matches : matches
                }
            }
        }

        func command(source: String) throws -> ToolCommand {
            let generator = regenerateTitle != nil
            let seed: (@Sendable (SeedContext) -> String)?
            if generator {
                seed = { context in
                    // Randomness is captured once per selection. The script maps
                    // these bytes to a versioned identifier or private seed.
                    let entropy = (0..<512).map { _ in UInt8.random(in: .min ... .max) }
                    return (try? ScriptRuntime.seed(id: id, source: source, context: context, entropy: entropy)) ?? ""
                }
            } else { seed = nil }
            return ToolCommand(id: id, title: title, summary: summary, group: ToolGroup(id: group, name: groupTitle),
                               icon: glyph.map(CommandIcon.glyph) ?? .symbol(symbol ?? "curlybraces"), aliases: aliases,
                               input: generator ? .none : .text, options: try (options ?? []).map { try $0.toolOption() },
                               copyNoun: { options in
                                   for (key, labels) in copyLabels ?? [:] {
                                       if let value = options.values[key], let label = labels[value] { return label }
                                   }
                                   return copyNoun
                               },
                               affinity: { profile in suggestions?.first { $0.matches(profile) }?.score ?? 0 },
                               makeSeed: seed, regenerateTitle: regenerateTitle) { request in
                do {
                    let data = try ScriptRuntime.evaluate(id: id, source: source, request: request)
                    if request.cancellation.isCancelled { return .cancelled }
                    return try ScriptRuntime.result(data, limits: request.limits)
                } catch is CancellationError { return .cancelled }
                catch { return .invalid(ToolDiagnostic(error.localizedDescription)) }
            }
        }
    }

    private static let entries: [(family: String, command: ToolCommand)] = {
        do {
            guard let folder = Bundle.module.url(forResource: "Scripts", withExtension: nil) else {
                throw ScriptFailure("The bundled tool resources are missing.")
            }
            let manifest = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: folder.appendingPathComponent("catalog.json")))
            guard manifest.apiVersion == 1 else { throw ScriptFailure("Unsupported bundled tool version.") }
            var sources: [String: String] = [:]
            for file in Set(manifest.commands.map(\.script)) {
                let libraries = manifest.libraries[file] ?? []
                sources[file] = try (libraries + [file]).map {
                    try sourceFile($0)
                }.joined(separator: "\n")
            }
            return try manifest.commands.map { ($0.script, try $0.command(source: sources[$0.script]!)) }
        } catch {
            // These resources are part of the signed build; CI exercises every
            // entry. Custom documents are validated separately and recoverably.
            preconditionFailure("Invalid bundled tool catalog: " + error.localizedDescription)
        }
    }()

    static func sourceFile(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Scripts") else {
            throw ScriptFailure("Missing bundled script: " + name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static var all: [ToolCommand] { entries.map(\.command) }
    static func commands(in family: String) -> [ToolCommand] {
        entries.filter { $0.family == family }.map(\.command)
    }
}

public struct ScriptOption: Codable, Sendable, Hashable {
    public struct Choice: Codable, Sendable, Hashable {
        public var id, label: String
        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }
    public var id, label, defaultValue: String
    public var choices: [Choice]?

    public init(id: String, label: String, defaultValue: String, choices: [Choice]? = nil) {
        self.id = id
        self.label = label
        self.defaultValue = defaultValue
        self.choices = choices
    }

    func toolOption() throws -> ToolOption {
        guard !id.isEmpty, !label.isEmpty else { throw ScriptFailure("Options require an identifier and label.") }
        if let choices {
            guard !choices.isEmpty, choices.count <= 32, choices.allSatisfy({ !$0.id.isEmpty && !$0.label.isEmpty }),
                  Set(choices.map(\.id)).count == choices.count, choices.contains(where: { $0.id == defaultValue }) else {
                throw ScriptFailure("Check the choices and default for " + label + ".")
            }
            return .choice(id, label, choices.map { .init($0.id, $0.label) }, default: defaultValue)
        }
        guard ["true","false"].contains(defaultValue) else { throw ScriptFailure("A toggle default must be true or false.") }
        return .toggle(id, label, default: defaultValue == "true")
    }
}
