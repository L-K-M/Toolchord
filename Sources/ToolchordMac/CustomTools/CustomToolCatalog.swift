import ToolchordCore

enum CustomToolCatalog {
    static let makerID = "toolchord.makeCustom"

    static let maker = ToolCommand(
        id: makerID, title: "Make Custom Tool", summary: "Describe a tool, try it, and add it to the palette",
        group: ToolGroup(id: "custom", name: "Custom Tools"), icon: .symbol("hammer"),
        aliases: ["create custom tool", "new tool", "javascript", "script", "edit custom tools"], input: .none,
        copyNoun: "result", evaluate: { _ in
            .unsupported("Press Return to describe a tool or edit your custom tools.")
        }
    )

    static func commands(for definitions: [ScriptToolDefinition]) throws -> [ToolCommand] {
        ToolCatalog.commands + [maker] + (try definitions.map { try $0.command() })
    }
}
