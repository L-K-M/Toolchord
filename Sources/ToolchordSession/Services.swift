import Foundation
import ToolchordCore

/// Runs a command away from the main actor. Injected so tests can control
/// completion order.
public protocol ToolEvaluating: Sendable {
    func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult
}

/// Evaluates on a detached task at user-initiated priority. Cancelling the
/// awaiting task cancels the evaluation cooperatively.
public struct BackgroundEvaluator: ToolEvaluating {
    public init() {}

    public func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult {
        let task = Task.detached(priority: .userInitiated) {
            var request = request
            request.cancellation = .currentTask
            return command.run(request)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Writes text to the system clipboard. Returns whether the write succeeded.
@MainActor
public protocol ClipboardWriting: AnyObject {
    func writeText(_ text: String, sensitivity: ClipboardSensitivity) -> Bool
}

/// Preferences the session reads. Never receives payloads or results.
@MainActor
public protocol SessionPreferences: AnyObject {
    /// Option values that replace a command's built-in defaults, such as the
    /// user's preferred JSON indentation.
    func defaultOptions(for command: ToolCommand) -> ToolOptions
    /// Most recent first. Command IDs only.
    var recentCommandIDs: [String] { get }
    func recordUse(of commandID: String)
}

/// Preferences kept in memory, for tests and previews.
@MainActor
public final class MemoryPreferences: SessionPreferences {
    public var overrides: [String: ToolOptions]
    public private(set) var recentCommandIDs: [String]
    public let recentLimit: Int

    public init(overrides: [String: ToolOptions] = [:], recentCommandIDs: [String] = [], recentLimit: Int = 4) {
        self.overrides = overrides
        self.recentCommandIDs = recentCommandIDs
        self.recentLimit = recentLimit
    }

    public func defaultOptions(for command: ToolCommand) -> ToolOptions {
        overrides[command.id] ?? ToolOptions()
    }

    public func recordUse(of commandID: String) {
        recentCommandIDs.removeAll { $0 == commandID }
        recentCommandIDs.insert(commandID, at: 0)
        if recentCommandIDs.count > recentLimit {
            recentCommandIDs.removeLast(recentCommandIDs.count - recentLimit)
        }
    }
}

/// A clipboard that records writes, for tests and previews.
@MainActor
public final class MemoryClipboard: ClipboardWriting {
    public private(set) var writes: [String] = []
    /// The sensitivity of each write, in the same order as ``writes``.
    public private(set) var sensitivities: [ClipboardSensitivity] = []
    public var failsWrites = false

    public init() {}

    public var text: String? { writes.last }

    public func writeText(_ text: String, sensitivity: ClipboardSensitivity) -> Bool {
        guard !failsWrites else { return false }
        writes.append(text)
        sensitivities.append(sensitivity)
        return true
    }
}
