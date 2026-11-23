import Foundation

enum BundledScripts {
    private struct Entry {
        let family: String
        let text: String
        let definition: ScriptToolDefinition
        let command: ToolCommand
    }

    private static let entries: [Entry] = {
        do {
            guard let directory = Bundle.module.url(forResource: "Scripts", withExtension: nil) else {
                throw ScriptFailure("The bundled tool resources are missing.")
            }
            let manager = FileManager.default
            let families = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                          options: .skipsHiddenFiles)
            let files = try families.filter(\.hasDirectoryPath).flatMap { family in
                try manager.contentsOfDirectory(at: family, includingPropertiesForKeys: nil,
                                                options: .skipsHiddenFiles).filter { $0.pathExtension == "js" }
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { throw ScriptFailure("No bundled tools were found.") }
            return try files.map { url in
                let text = try String(contentsOf: url, encoding: .utf8)
                let definition = try ToolScriptDocument(text: text).definition
                let name = url.deletingPathExtension().lastPathComponent
                let parts = name.split(separator: "-", maxSplits: 1)
                guard parts.count == 2, Int(parts[0]) != nil, String(parts[1]).hasSameUTF8(as: definition.id) else {
                    throw ScriptFailure("The tool ID must match its bundled filename: " + name)
                }
                return try Entry(family: url.deletingLastPathComponent().lastPathComponent, text: text,
                                 definition: definition, command: definition.bundledCommand())
            }
        } catch {
            // A broken signed resource is a build error. User files are validated separately.
            preconditionFailure("Invalid bundled tool catalog: " + error.localizedDescription)
        }
    }()

    static var all: [ToolCommand] { entries.map(\.command) }
    static var definitions: [ScriptToolDefinition] { entries.map(\.definition) }

    static func scriptText(id: String) -> String? {
        entries.first { $0.definition.id == id }?.text
    }

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
