import Foundation

/// Optional search, presentation, and input suggestions declared in a tool header.
public struct ScriptPalette: Codable, Hashable, Sendable {
    public var group: String?
    public var groupTitle: String?
    public var aliases: [String]?
    public var symbol: String?
    public var glyph: String?
    public var copyNoun: String?
    public var copyLabels: [String: [String: String]]?
    public var suggestions: [Suggestion]?

    public struct Suggestion: Codable, Sendable, Hashable {
        public var when: [String]
        public var score: Int

        public init(when: [String], score: Int) {
            self.when = when
            self.score = score
        }

        fileprivate func matches(_ profile: InputProfile) -> Bool {
            when.allSatisfy { condition in
                let negative = condition.hasPrefix("!")
                let kind = negative ? String(condition.dropFirst()) : condition
                let matches: Bool
                if kind == "plain" {
                    matches = profile.isPlainText
                } else {
                    matches = InputKind(rawValue: kind).map(profile.has) == true
                }
                return negative ? !matches : matches
            }
        }
    }

    public init() {}

    var toolGroup: ToolGroup { ToolGroup(id: group ?? "custom", name: groupTitle ?? group ?? "Custom") }
    var icon: CommandIcon { glyph.map(CommandIcon.glyph) ?? .symbol(symbol ?? "curlybraces") }

    func validate() throws {
        let labels = [group, groupTitle, symbol, glyph, copyNoun].compactMap { $0 }
        guard labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              (aliases ?? []).count <= 64,
              (aliases ?? []).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            throw ScriptFailure("Use short palette labels and up to 64 search aliases.")
        }
        let rules = suggestions ?? []
        guard rules.count <= 32, rules.allSatisfy({ rule in
            (0...100).contains(rule.score) && rule.when.count <= 16 && rule.when.allSatisfy { condition in
                let name = condition.hasPrefix("!") ? String(condition.dropFirst()) : condition
                return name == "plain" || InputKind(rawValue: name) != nil
            }
        }) else {
            throw ScriptFailure("Check palette suggestion conditions and scores (0 to 100).")
        }
        let nouns = copyLabels ?? [:]
        guard nouns.count <= 16, nouns.allSatisfy({ option, choices in
            !option.isEmpty && option.utf8.count <= 128 && choices.count <= 32 && choices.allSatisfy { value, label in
                !value.isEmpty && value.utf8.count <= 128 && !label.isEmpty && label.utf8.count <= 128
            }
        }) else {
            throw ScriptFailure("Check the option IDs and copy labels in the palette header.")
        }
    }

    /// Returns the first suggestion score whose conditions match the profile.
    func affinity(for profile: InputProfile) -> Int {
        suggestions?.first { $0.matches(profile) }?.score ?? 0
    }

    /// Resolves the copy noun from option values, falling back to the declared
    /// noun and finally to "result".
    func copyNoun(for options: ToolOptions) -> String {
        let labels = copyLabels ?? [:]
        for key in labels.keys.sorted() {
            if let value = options.values[key], let label = labels[key]?[value] {
                return label
            }
        }
        return copyNoun ?? "result"
    }
}
