/// Bundled JavaScript commands for the hex tool family.
public enum HexTools {
    public static var commands: [ToolCommand] { BundledScripts.commands(in: "hex") }
}
