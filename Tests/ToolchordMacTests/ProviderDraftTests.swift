import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor @Suite struct ProviderDraftTests {
    @Test func sharedScriptRevisionNamesTheEditedCommand() throws {
        let tool = try #require(ToolCatalog.bundledDefinitions.first { $0.id == "json.format" })
        let prompt = try AuthoringPrompt.request(description: "Use tabs", current: tool, isNew: false)
        #expect(prompt.contains("api.id is json.format"))
    }

    @Test func generatedProgramCanBeTriedAndRevisedWithoutChangingIdentity() throws {
        let id = "custom.external"
        let reply = #"""
        ```json
        {"id":"custom.untrusted","title":"Double","summary":"Repeat the input","isGenerator":false,
         "previewBody":"return repeatText(input);","helpers":"function repeatText(text) { return text + text; }",
         "actions":[{"id":"copy","title":"Copy first"}],"performBody":"api.clipboard.writeText(input);"}
        ```
        """#
        let draft = try ProviderScriptGenerator.parse(reply, id: id)
        #expect(draft.id == id)
        let command = try draft.command()
        #expect(command.run(.init(text: " A ")).output?.primaryText == " A  A ")
        #expect(command.performScriptAction(id: "copy", request: .init(text: " A ")).output?.primaryText == " A ")
        let fresh = try AuthoringPrompt.request(description: "Make a new tool", current: draft, isNew: true)
        let revision = try AuthoringPrompt.request(description: "Repeat three times", current: draft, isNew: false)
        #expect(!fresh.contains("repeatText"))
        #expect(revision.contains("repeatText"))
        #expect(!revision.contains(id))
    }

    @Test func malformedAndIncompleteRepliesLeaveTheDraftUnchanged() {
        let responses = ["an explanation instead of JSON",
                         #"{"title":"T","summary":"","isGenerator":false,"previewBody":"return ( ;"}"#,
                         #"{"title":"T","summary":"","isGenerator":true,"previewBody":"return api.seed;"}"#,
                         #"{"title":"T","summary":"","isGenerator":false,"previewBody":"return input;","actions":[{"id":"x","title":"X"}]}"#]
        for response in responses {
            #expect(throws: (any Error).self) { try ProviderScriptGenerator.parse(response, id: "custom.test") }
        }
    }
}
