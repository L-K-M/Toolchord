public enum MarkupTools {
    public static var commands: [ToolCommand] { BundledScripts.commands(in: "markup") }
}

/// The platform parser can stop on cancellation or a configured depth limit.
enum MarkupFailure: Error { case cancelled, nesting }
