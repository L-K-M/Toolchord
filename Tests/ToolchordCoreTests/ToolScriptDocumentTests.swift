import Foundation
import Testing
@testable import ToolchordCore

@Suite struct ToolScriptDocumentTests {
    @Test func handwrittenHeaderKeepsExactBodyAndUnknownMetadata() throws {
        let source = "\r\nfunction preview() { return '☕️'; }\r\n"
        let text = "\u{feff}/* @toolchord\r\n" +
            #"{"apiVersion":1,"id":"custom.test","title":"Coffee","extension":{"owner":"Ada"}}"# +
            "\r\n*/\r\n" + source
        let document = try ToolScriptDocument(text: text)
        #expect(document.definition.source.utf8.elementsEqual(source.utf8))
        #expect(document.definition.title == "Coffee")
        #expect(document.definition.actions.isEmpty && document.definition.capabilities.isEmpty)
        let header = try #require(JSONSerialization.jsonObject(with: document.metadata) as? [String: Any])
        #expect(header["extension"] as? [String: String] == ["owner": "Ada"])
        #expect(header["source"] == nil)
    }

    @Test func blockCommentTerminatorStaysInsideJSON() throws {
        let tool = ScriptToolDefinition(id: "custom.comment", title: "Escape */ in JSON",
                                        source: "function preview() { return '*/'; }")
        let text = try ToolScriptDocument.text(for: tool)
        let separator = try #require(text.range(of: "*/"))
        #expect(text[separator.upperBound...] == "\n" + tool.source)
        #expect(try ToolScriptDocument(text: text).definition == tool)
    }

    @Test func malformedBodyCanBeOpenedForRepair() throws {
        let tool = ScriptToolDefinition(id: "custom.repair", title: "Repair", source: "function preview( {")
        let draft = try ToolScriptDocument(text: ToolScriptDocument.text(for: tool))
        #expect(draft.definition.source == tool.source)
        #expect(throws: (any Error).self) { try draft.definition.validate() }
    }

    @Test func wrongTypeIdentifiesItsField() {
        let header = #"{"apiVersion":1,"id":"custom.bad","title":"Tool","options":"unfinished"}"#
        do {
            _ = try ToolScriptDocument(text: "/* @toolchord\n" + header + "\n*/\n")
            Issue.record("Accepted a non-array options field.")
        } catch {
            #expect(error.localizedDescription.contains("options"))
        }
    }

    private static let invalidHeaders: [String] = [
        "throw Error('run on load')", "/* @toolchord\n[]\n*/\n",
        #"/* @toolchord"# + "\n" + #"{"apiVersion":1,"id":"custom.x","title":"Tool","source":"injected"}"# + "\n*/\n",
        "/* @toolchord\n" + #"{"apiVersion":1,"id":"custom.x","title":"*/ premature close"}"# + "\n*/\n",
        "/* @toolchord\n" + #"{"apiVersion":1,"id":"custom.x","title":"Tool"}"# + "\n*/alert(1)",
        "/* @toolchord\n{}\n*/\n", "/* @toolchord\n{ invalid }\n*/\n"
    ]

    @Test(arguments: invalidHeaders)
    func rejectsInvalidHeaders(_ text: String) {
        #expect(throws: (any Error).self) { try ToolScriptDocument(text: text) }
    }
}
