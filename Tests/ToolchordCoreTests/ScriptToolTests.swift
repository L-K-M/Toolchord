import Foundation
import Testing
@testable import ToolchordCore

@Suite struct ScriptToolTests {
    private let definition = ScriptToolDefinition(
        id: "custom.list-difference", title: "Compare IDs", source: """
        function difference(text) {
            const [before, after] = text.split(/\\n\\n/).map(list => new Set(list.split("\\n")));
            return [...after].filter(id => !before.has(id)).join("\\n");
        }
        function preview(input, options, api) {
            if (api.clipboard) throw Error("Preview has access to the clipboard");
            return { primaryText: difference(input), status: "Added IDs" };
        }
        function perform(action, input, options, api) {
            api.clipboard.writeText(difference(input));
        }
        """, actions: [.init(id: "copyAdded", title: "Copy Additions")], capabilities: ["clipboard.write"])

    @Test func savedJavaScriptRunsInBothModes() throws {
        let saved = try JSONEncoder().encode(definition)
        let command = try JSONDecoder().decode(ScriptToolDefinition.self, from: saved).command()
        let request = ToolRequest(text: "a\nb\n\nb\nc\nd")
        let preview = command.run(request)
        #expect(preview.output?.primaryText == "c\nd", "Actual: \(preview)")
        #expect(command.performScriptAction(id: "copyAdded", request: request).output?.primaryText == "c\nd")
        #expect(command.performScriptAction(id: "undeclared", request: request).output == nil)
    }

    @Test func exceptionAfterWriteDiscardsAction() throws {
        var broken = definition
        broken.source = "function preview() {return ''} function perform(a,i,o,api){api.clipboard.writeText('x'); throw Error('failed');}"
        #expect(try broken.command().performScriptAction(id: "copyAdded", request: ToolRequest(text: "")).problem?.contains("failed") == true)
    }

    @Test func missingActionHandlerIsReportedDuringTrial() throws {
        var tool = definition
        tool.source = "function preview() { return 'ready'; }"
        let result = try tool.command().run(.init(text: "x"))
        #expect(result.problem?.contains("perform") == true)
    }

    @Test func invalidClipboardPolicyIsReported() throws {
        var tool = definition
        tool.actions = []
        tool.source = "function preview() { return { primaryText: 'x', sensitivity: 'private' }; }"
        let result = try tool.command().run(.init(text: "x"))
        #expect(result.problem?.contains("clipboard") == true)
    }

    @Test func invalidDocumentsCannotRegister() throws {
        var broken = definition
        broken.id = "json.format"
        #expect(throws: (any Error).self) { try broken.command() }
        broken = definition
        broken.source = "function preview("
        #expect(throws: (any Error).self) { try broken.command() }
        broken = definition
        broken.capabilities = []
        #expect(throws: (any Error).self) { try broken.command() }
    }

    @Test func runawayToolCanBeCancelled() async throws {
        var looping = definition
        looping.actions = []
        looping.source = "function preview(){while(true){} }"
        let command = try looping.command()
        let task = Task.detached { command.run(.init(input: .text(""), cancellation: .currentTask)) }
        // The synchronous evaluation can occupy the sole cooperative thread
        // on a small runner. Deliver cancellation independently, as the UI does.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(250)) {
            task.cancel()
        }
        let result = await task.value
        #expect(result == .cancelled)
    }
}
