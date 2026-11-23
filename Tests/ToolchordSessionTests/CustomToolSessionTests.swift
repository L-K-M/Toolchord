import Foundation
import Observation
import Testing
import ToolchordCore
@testable import ToolchordSession

@MainActor
@Suite struct CustomToolSessionTests {
    private func script() throws -> ToolCommand {
        try ScriptToolDefinition(
            id: "custom.actions", title: "Uppercase Copy", source: """
            function preview(input) { return input; }
            function perform(action, input, options, api) { api.clipboard.writeText(input.toUpperCase()); }
            """, actions: [.init(id: "copy", title: "Copy Uppercase")], capabilities: ["clipboard.write"]
        ).command()
    }

    @Test func previewIsPureAndOnlyExplicitKnownActionWritesClipboard() async throws {
        let clipboard = MemoryClipboard()
        let session = PaletteSession(catalog: [try script()], clipboard: clipboard, preferences: MemoryPreferences())
        session.attach("hello")
        await session.waitForIdle()
        #expect(clipboard.writes.isEmpty)
        #expect(session.copyableOutput?.primaryText == "hello")
        #expect(await session.performScriptAction("unknown") == .unavailable)
        #expect(clipboard.writes.isEmpty)
        #expect(await session.performScriptAction("copy") == .copied)
        #expect(clipboard.writes == ["HELLO"])
        #expect(session.payload?.text == "hello")
    }

    @Test func changedInputRetiresPendingActionBeforeItCanCopy() async throws {
        let clipboard = MemoryClipboard()
        let session = PaletteSession(catalog: [try script()], clipboard: clipboard, preferences: MemoryPreferences())
        session.attach("old")
        await session.waitForIdle()
        try #require(session.canCopy)
        let action = Task { await session.performScriptAction("copy") }
        try await waitForAction(session)
        session.editInput("new")
        #expect(await action.value == .unavailable)
        #expect(clipboard.writes.isEmpty)
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "new")
    }

    @Test func dismissalRetiresPendingActionAndFailedWriteStaysInSession() async throws {
        let clipboard = MemoryClipboard()
        let session = PaletteSession(catalog: [try script()], clipboard: clipboard, preferences: MemoryPreferences())
        session.attach("old")
        await session.waitForIdle()
        try #require(session.canCopy)
        let action = Task { await session.performScriptAction("copy") }
        try await waitForAction(session)
        session.end()
        #expect(await action.value == .unavailable)
        #expect(clipboard.writes.isEmpty)
        session.attach("current")
        await session.waitForIdle()
        clipboard.failsWrites = true
        #expect(await session.performScriptAction("copy") == .failed)
        #expect(session.payload?.text == "current")
        #expect(session.notice?.kind == .error)
    }

    @Test func replacementWithSameIdentityInvalidatesOutputAndPreservesDraft() async {
        let clipboard = MemoryClipboard()
        func command(_ suffix: String) -> ToolCommand {
            ToolCommand(id: "custom.replace", title: "Replace " + suffix, summary: "", group: .init(id: "custom", name: "Custom"), icon: .glyph("JS"), copyNoun: "text") {
                .success(ToolOutput(primaryText: ($0.input.text ?? "") + suffix, status: "Ready"))
            }
        }
        let session = PaletteSession(catalog: [command("1")], evaluator: InlineEvaluator(), clipboard: clipboard, preferences: MemoryPreferences())
        session.attach("draft")
        session.openSelected()
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "draft1")
        let observation = SelectionObservation()
        withObservationTracking {
            _ = session.selectedCommand?.title
        } onChange: {
            MainActor.assumeIsolated { observation.didChange = true }
        }
        session.replaceCatalog([command("2")])
        #expect(observation.didChange)
        #expect(session.selectedCommand?.title == "Replace 2")
        #expect(!session.canCopy)
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "draft2")
        #expect(session.payload?.text == "draft")
        #expect(session.isInTool)
        session.replaceCatalog([])
        #expect(!session.isInTool)
        #expect(session.selectedID == nil)
        #expect(!session.canCopy)
    }

    @Test func replacingGeneratorReseedsOnlyChangedImplementations() async throws {
        func generator(_ value: String) -> ToolCommand {
            ToolCommand(id: "uuid.v4", title: "Generator", summary: "", group: .init(id: "uuid", name: "UUID"),
                        icon: .glyph("G"), input: .none, copyNoun: "value", makeSeed: { _ in value }) {
                .success(ToolOutput(primaryText: $0.seed ?? "", status: "Ready"))
            }
        }
        let original = generator("original")
        let session = PaletteSession(catalog: [original], evaluator: InlineEvaluator(), clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.activate()
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "original")
        session.replaceCatalog([generator("edited")])
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "edited")
        session.replaceCatalog([original])
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "original")

        let uuid = try #require(ToolCatalog.command(id: "uuid.v4"))
        session.replaceCatalog([uuid])
        await session.waitForIdle()
        let stable = try #require(session.copyableOutput?.primaryText)
        session.replaceCatalog([uuid, try script()])
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == stable)
    }

    private func waitForAction(_ session: PaletteSession) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !session.isPerformingScriptAction, ContinuousClock.now < deadline { await Task.yield() }
        try #require(session.isPerformingScriptAction)
    }

    @MainActor private final class SelectionObservation {
        var didChange = false
    }
}
