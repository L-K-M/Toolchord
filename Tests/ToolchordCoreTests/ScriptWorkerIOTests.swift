import Foundation
import Testing
@testable import ToolchordCore

@Suite(.timeLimit(.minutes(1)))
struct ScriptWorkerIOTests {
    @Test func requestAndResponseExceedPipeCapacity() throws {
        let input = String(repeating: "a\\b\n\"😀", count: 16_384)
        let definition = ScriptToolDefinition(id: "custom.large-pipes", title: "Large pipes", source: """
        function preview(input) { return {primaryText: input + input, status: 'Round trip'}; }
        """)
        let command = try definition.command()
        let result = command.run(ToolRequest(text: input))
        let output = try #require(result.output, "Actual result: \(result)")
        #expect(output.primaryText.hasSameUTF8(as: input + input))
        #expect(output.status == "Round trip")
    }

    /// Also run with LIBDISPATCH_COOPERATIVE_POOL_STRICT=1: pipe progress must
    /// not require a dispatch block to run while this task waits for its child.
    @Test func concurrentWorkersCompleteWithoutDispatchAssistance() async throws {
        let definition = ScriptToolDefinition(id: "custom.concurrent-pipes", title: "Concurrent pipes", source: """
        function preview(input) { return input + ':returned'; }
        """)
        let command = try definition.command()
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let input = "\(index):" + String(repeating: "x", count: 96 * 1024)
                    return command.run(ToolRequest(text: input)).output?.primaryText == input + ":returned"
                }
            }
            for await succeeded in group { #expect(succeeded) }
        }
    }

    @Test func cancellationClosesPartiallySentRequests() throws {
        let definition = ScriptToolDefinition(id: "custom.cancel-pipe", title: "Cancel pipe", source: """
        function preview(input) { return input; }
        """)
        let command = try definition.command()
        let input = String(repeating: "x", count: 512 * 1024)
        let cancelAt = ContinuousClock.now + .milliseconds(1)
        let result = command.run(ToolRequest(input: .text(input), cancellation: CancellationCheck { ContinuousClock.now >= cancelAt }))
        #expect(result == .cancelled)
        #expect(command.run(ToolRequest(text: "healthy")).output?.primaryText == "healthy")
    }
}
