import Foundation
import ToolchordCore

enum CustomToolCatalog {
    static let bundledByID = Dictionary(uniqueKeysWithValues: ToolCatalog.bundledDefinitions.map { ($0.id, $0) })

    static let makerID = "toolchord.makeCustom"

    static let maker = ToolCommand(
        id: makerID, title: "Make Custom Tool", summary: "Describe a tool, try it, and add it to the palette",
        group: ToolGroup(id: "custom", name: "Custom Tools"), icon: .symbol("hammer"),
        aliases: ["create custom tool", "new tool", "javascript", "script", "edit custom tools"], input: .none,
        copyNoun: "result", evaluate: { _ in
            .unsupported("Press Return to describe a tool or edit your custom tools.")
        }
    )

    /// Preserve manifest order and command identities when applying local edits.
    static func commands(including installed: [String: ToolCommand]) -> [ToolCommand] {
        var custom = installed
        let builtIns = ToolCatalog.commands.map { command in custom.removeValue(forKey: command.id) ?? command }
        return builtIns + [maker] + custom.values.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
