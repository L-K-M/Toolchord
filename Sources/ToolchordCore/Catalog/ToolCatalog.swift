/// The signed catalog, in manifest order. A palette session can add locally
/// authored commands without mutating this shared list.
public enum ToolCatalog {
    public static let commands = BundledScripts.all

    public static func command(id: String) -> ToolCommand? {
        commands.first { $0.id == id }
    }
}
