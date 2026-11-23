import Foundation

/// A family of related commands, such as all JSON commands. Groups order the
/// catalog and give search an extra word to match ("json", "base64").
public struct ToolGroup: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A command's list icon: a short monospaced glyph such as `{ }`, or an SF
/// Symbol name for the Mac UI.
public enum CommandIcon: Sendable, Hashable {
    case glyph(String)
    case symbol(String)
}

/// Lets long-running evaluation stop early when its result can no longer be
/// published. Tools check it in loops over large input.
public struct CancellationCheck: Sendable {
    private let check: @Sendable () -> Bool

    public init(_ check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    public var isCancelled: Bool { check() }

    public static let never = CancellationCheck { false }
    /// Uses the current Swift task's cancellation state.
    public static let currentTask = CancellationCheck { Task.isCancelled }
}

/// Everything one evaluation may depend on. Evaluation is a pure function of
/// this value, so tests can fix the clock and time zone.
public struct ToolRequest: Sendable {
    public var input: ToolInput
    /// Resolved options: every declared option is present and valid.
    public var options: ToolOptions
    /// The session's generated value for generator commands (for example the
    /// UUID shown on screen). `nil` for transforms.
    public var seed: String?
    public var now: Date
    public var timeZone: TimeZone
    public var limits: ToolLimits
    public var cancellation: CancellationCheck

    public init(
        input: ToolInput,
        options: ToolOptions = ToolOptions(),
        seed: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        limits: ToolLimits = .standard,
        cancellation: CancellationCheck = .never
    ) {
        self.input = input
        self.options = options
        self.seed = seed
        self.now = now
        self.timeZone = timeZone
        self.limits = limits
        self.cancellation = cancellation
    }

    /// Convenience for tests and previews: attached text.
    public init(text: String, options: [String: String] = [:], now: Date = Date(), timeZone: TimeZone = .current) {
        self.init(input: .text(text), options: ToolOptions(options), now: now, timeZone: timeZone)
    }
}

/// Context for creating a generator's value on first selection or Regenerate.
public struct SeedContext: Sendable {
    public var now: Date
    public var options: ToolOptions

    public init(now: Date = Date(), options: ToolOptions = ToolOptions()) {
        self.now = now
        self.options = options
    }
}

/// One searchable, verb-first action such as "Format JSON".
///
/// A command declares its input requirement, options, primary copy target,
/// and how strongly it applies to detected input. Evaluation must be
/// deterministic for a given ``ToolRequest`` and must not touch the
/// clipboard, the network, the file system, or logs.
public struct ToolCommand: Sendable, Identifiable {
    /// A signed generator and its local replacement can use different seed formats.
    /// Copies of the same implementation can keep their session seed across reloads.
    package let implementationID = UUID()
    /// Stable identifier, `group.action`, such as `json.format`.
    public let id: String
    /// Verb-first title shown in the list, such as "Format JSON".
    public let title: String
    /// One short line explaining what the command does.
    public let summary: String
    public let group: ToolGroup
    public let icon: CommandIcon
    /// Extra search terms, such as "pretty print" or "epoch".
    public let aliases: [String]
    public let input: InputRequirement
    public let options: [ToolOption]
    /// Names the primary result in "Copy ‹noun› & Close", for example "JSON",
    /// "input", or "UUID". Depends only on options.
    public let copyNoun: @Sendable (ToolOptions) -> String
    /// How strongly the command applies to detected input. 0 means "not
    /// suggested"; suggestions are ordered by descending affinity.
    public let affinity: @Sendable (InputProfile) -> Int
    /// Creates the generated value for `input == .none` commands. Called on
    /// first selection within a session and on Regenerate.
    public let makeSeed: (@Sendable (SeedContext) -> String)?
    /// Label for the regenerate action, such as "Regenerate UUID".
    public let regenerateTitle: String?
    public let evaluate: @Sendable (ToolRequest) -> ToolResult

    public init(
        id: String,
        title: String,
        summary: String,
        group: ToolGroup,
        icon: CommandIcon,
        aliases: [String] = [],
        input: InputRequirement = .text,
        options: [ToolOption] = [],
        copyNoun: @escaping @Sendable (ToolOptions) -> String,
        affinity: @escaping @Sendable (InputProfile) -> Int = { _ in 0 },
        makeSeed: (@Sendable (SeedContext) -> String)? = nil,
        regenerateTitle: String? = nil,
        evaluate: @escaping @Sendable (ToolRequest) -> ToolResult
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.group = group
        self.icon = icon
        self.aliases = aliases
        self.input = input
        self.options = options
        self.copyNoun = copyNoun
        self.affinity = affinity
        self.makeSeed = makeSeed
        self.regenerateTitle = regenerateTitle
        self.evaluate = evaluate
    }

    /// Convenience for commands whose copy target does not depend on options.
    public init(
        id: String,
        title: String,
        summary: String,
        group: ToolGroup,
        icon: CommandIcon,
        aliases: [String] = [],
        input: InputRequirement = .text,
        options: [ToolOption] = [],
        copyNoun: String,
        affinity: @escaping @Sendable (InputProfile) -> Int = { _ in 0 },
        makeSeed: (@Sendable (SeedContext) -> String)? = nil,
        regenerateTitle: String? = nil,
        evaluate: @escaping @Sendable (ToolRequest) -> ToolResult
    ) {
        self.init(
            id: id, title: title, summary: summary, group: group, icon: icon, aliases: aliases,
            input: input, options: options, copyNoun: { _ in copyNoun }, affinity: affinity,
            makeSeed: makeSeed, regenerateTitle: regenerateTitle, evaluate: evaluate
        )
    }

    public internal(set) var scriptActions: [ScriptToolAction] = []
    var scriptActionHandler: (@Sendable (String, ToolRequest) -> ToolResult)?

    /// Returns the requested write as data. Only the session may commit it,
    /// after checking that the user action still belongs to this revision.
    public func performScriptAction(id: String, request: ToolRequest) -> ToolResult {
        guard let handler = scriptActionHandler else { return .unsupported("This tool has no actions.") }
        if input == .text && request.input.text == nil { return .needsInput("Attach text to use this action.") }
        guard (request.input.text?.utf8.count ?? 0) <= request.limits.maxInputBytes else { return .tooLarge(request.limits.inputLimitMessage) }
        var request = request
        request.options = request.options.resolved(for: options)
        return handler(id, request)
    }

    public var isGenerator: Bool { input == .none }

    /// "Copy JSON & Close".
    public func copyAndCloseTitle(options: ToolOptions) -> String {
        "Copy \(copyNoun(options.resolved(for: self.options))) & Close"
    }

    /// Evaluates with resolved options and the standard input-size check.
    /// The session calls this off the main thread.
    public func run(_ request: ToolRequest) -> ToolResult {
        var request = request
        request.options = request.options.resolved(for: options)
        if input == .text {
            guard let text = request.input.text else {
                return .needsInput("Paste text to use \(title).")
            }
            if text.utf8.count > request.limits.maxInputBytes {
                return .tooLarge(request.limits.inputLimitMessage)
            }
        }
        let result = evaluate(request)
        if let output = result.output {
            if let tooLarge = request.limits.checkOutput(output.primaryText) { return tooLarge }
            // Copyable fields are copy targets too.
            if output.fields.contains(where: { $0.value.utf8.count > request.limits.maxOutputBytes }) {
                return .tooLarge(request.limits.outputLimitMessage)
            }
        }
        return result
    }
}
