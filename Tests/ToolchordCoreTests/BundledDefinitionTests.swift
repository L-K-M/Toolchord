import Foundation
import Testing
@testable import ToolchordCore

@Suite struct BundledDefinitionTests {
    @Test func everyBundledProgramRunsAsAPortableDocument() throws {
        let definitions = ToolCatalog.bundledDefinitions
        #expect(definitions.map(\.id) == ToolCatalog.commands.map(\.id))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entropy = (0..<512).map { UInt8(truncatingIfNeeded: $0) }

        for (original, signed) in zip(definitions, ToolCatalog.commands) {
            let bytes = try JSONEncoder().encode(original)
            let document = try JSONDecoder().decode(ScriptToolDefinition.self, from: bytes)
            let editable = try document.command()
            let sample = sampleText(for: signed)
            let profile = InputDetector.profile(for: sample)
            let options = ToolOptions(["prefix": "true", "format": "ms", "characters": "hex"]).resolved(for: signed.options)
            #expect(editable.title == signed.title)
            #expect(editable.summary == signed.summary)
            #expect(editable.aliases == signed.aliases)
            #expect(editable.group == signed.group)
            #expect(editable.icon == signed.icon)
            #expect(editable.options == signed.options)
            #expect(editable.regenerateTitle == signed.regenerateTitle)
            #expect(editable.affinity(profile) == signed.affinity(profile))
            #expect(editable.copyAndCloseTitle(options: options) == signed.copyAndCloseTitle(options: options))

            var request = ToolRequest(input: signed.isGenerator ? .none : .text(sample),
                                      options: options, now: now, timeZone: .gmt)
            var isolatedRequest = request
            if signed.isGenerator {
                let context = SeedContext(now: now, options: options)
                request.seed = try ScriptRuntime.seed(id: signed.id, source: document.source, context: context, entropy: entropy)
                isolatedRequest.seed = ScriptWorker.captureSeed(context, entropy: entropy)
                #expect(editable.makeSeed != nil)
            }
            let expected = signed.run(request)
            let actual = editable.run(isolatedRequest)
            #expect(expected.isSuccess, "\(signed.id): \(expected)")
            #expect(actual == expected, "\(signed.id): \(actual)")
            if signed.id == "random.string" { #expect(actual.output?.sensitivity == .secret) }
        }
    }

    @Test func builtInIdentityStillUsesWorkerResultValidation() throws {
        var tool = try #require(ToolCatalog.bundledDefinitions.first { $0.id == "json.format" })
        tool.source = "function preview() { return {primaryText: 'edited', status: 'x'.repeat(4097)}; }"
        let result = try tool.command().run(.init(text: "{}"))
        #expect(result.problem?.contains("too much display text") == true)
    }

    private func sampleText(for command: ToolCommand) -> String {
        switch command.id {
        case "jwt.decode": return "eyJhbGciOiJub25lIn0.eyJleHAiOjB9."
        case "time.fromUnix": return "1700000000"
        case "time.toUnix": return "2024-01-01T00:00:00Z"
        case "base64.decode", "base64url.decode": return "SGVsbG8="
        case "hex.decode": return "48656c6c6f"
        case "json.unescapeString": return #""hello\nworld""#
        case "url.inspect": return "https://example.test/?a=1&a=2"
        default: break
        }
        switch command.group.id {
        case "json": return #"{"a":1}"#
        case "xml", "escape", "plaintext": return "<p>Hello world</p>"
        case "number": return "42"
        case "color": return "#f80"
        case "markdown": return "**Hello!**"
        default: return "Hello, world!\nAgain."
        }
    }
}
