import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
private struct StubGenerator: ScriptGenerating {
    var unavailableReason: String? = nil
    let generateDraft: (String, ScriptToolDefinition, Bool) async throws -> ScriptToolDefinition

    func generate(description: String, current: ScriptToolDefinition, isNew: Bool) async throws -> ScriptToolDefinition {
        try await generateDraft(description, current, isNew)
    }
}

@MainActor @Suite struct AuthoringProviderEditorTests {
    @Test func selectedEndpointGeneratesWithUnavailableAppleModelAndKeepsDraftOnFailure() async throws {
        let suite = "ToolchordTests.authoring-routing.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AuthoringProviderSettings(defaults: defaults)
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let unavailable = StubGenerator(unavailableReason: "Apple Intelligence unavailable") { _, _, _ in
            Issue.record("Apple Intelligence was called after selecting the endpoint")
            throw ToolDiagnostic("Unexpected generator")
        }
        var calls: [[String]] = []
        let editor = CustomToolEditorModel(library: library, generator: unavailable, providers: settings) { provider, endpoint, model in
            calls.append([provider, endpoint, model])
            return StubGenerator { description, current, isNew in
                if !isNew { throw ToolDiagnostic("Endpoint unavailable") }
                #expect(description == "Uppercase my text")
                var revised = current
                revised.title = "Uppercase"
                revised.source = "function preview(input) { return input.toUpperCase(); }"
                return revised
            }
        }
        editor.description = "Uppercase my text"
        editor.sampleInput = "only sample"
        settings.select(.endpoint)
        #expect(settings.useEndpoint("https://example.com/"))
        editor.generate()
        #expect(calls.isEmpty)
        settings.setModel("user-specified-model")
        editor.generate()
        await editor.waitForIdle()
        #expect(!editor.isError)
        #expect(calls == [["endpoint", "https://example.com/v1", "user-specified-model"]])
        editor.runSample()
        await editor.waitForIdle()
        #expect(editor.trialResult?.output?.primaryText == "ONLY SAMPLE")
        editor.save()
        let saved = editor.definition
        editor.description = "Keep commas"
        editor.generate()
        await editor.waitForIdle()
        #expect(editor.isError)
        #expect(editor.definition == saved)
        #expect(editor.description == "Keep commas")
        #expect(library.definitions == [saved])
    }

    @Test func switchingHarnessDuringGenerationKeepsCurrentDraft() async throws {
        let suite = "ToolchordTests.authoring-switch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AuthoringProviderSettings(defaults: defaults)
        settings.select(.codex)
        let entered = AsyncStream<Void>.makeStream()
        let released = AsyncStream<Void>.makeStream()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, providers: settings) { provider, _, model in
            #expect(provider == "codex" && model.isEmpty)
            return StubGenerator { _, current, _ in
                entered.continuation.finish()
                for await _ in released.stream {}
                var changed = current
                changed.title = "Old result"
                return changed
            }
        }
        let original = editor.definition
        editor.description = "Make an acronym"
        editor.generate()
        for await _ in entered.stream {}
        settings.select(.claude)
        released.continuation.finish()
        await editor.waitForIdle()
        #expect(!editor.isGenerating && editor.isError)
        #expect(editor.definition == original)
        #expect(editor.description == "Make an acronym")
    }
}
