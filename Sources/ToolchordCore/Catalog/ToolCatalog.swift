/// The signed catalog, in palette order. A palette session can add locally
/// authored commands without mutating this shared list.
public enum ToolCatalog {
    public static let commands = BundledScripts.all
    private static let commandsByID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })

    /// Editable and exportable programs in palette order, with their shared JavaScript helpers included.
    public static let bundledDefinitions = BundledScripts.definitions

    /// The exact standalone JavaScript file shipped in the app.
    public static func bundledScriptText(id: String) -> String? { BundledScripts.scriptText(id: id) }

    public static func command(id: String) -> ToolCommand? {
        commandsByID[id]
    }
}
