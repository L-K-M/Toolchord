import Foundation
import Testing
@testable import ToolchordMac
import ToolchordCore

/// Opt in on a Mac with its local language model installed. CI uses deterministic
/// editor tests; this check exercises the installed model and the real worker.
@Suite @MainActor struct LiveAuthoringTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOLCHORD_TEST_LOCAL_MODEL"] == "1"))
    func describeTrySaveAndRevise() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptToolStore(directoryURL: directory)
        let library = CustomToolLibrary(store: store)
        let editor = CustomToolEditorModel(library: library)
        editor.description = "Wrap the entire input string between a literal [ and ]. Preserve spaces. No options or actions."
        editor.generate()
        await editor.waitForIdle()
        try #require(!editor.isError, "\(editor.message ?? "Generation failed")")
        editor.sampleInput = " A17 "
        editor.runSample()
        await editor.waitForIdle()
        try #require(editor.trialResult?.output?.primaryText == "[ A17 ]", "\(String(describing: editor.trialResult))")
        editor.save()
        let original = try #require(try store.load().first)

        editor.description = "Change the brackets to parentheses so the same tool wraps the entire original input between ( and )."
        editor.generate()
        await editor.waitForIdle()
        try #require(!editor.isError, "\(editor.message ?? "Revision failed")")
        editor.runSample()
        await editor.waitForIdle()
        try #require(editor.trialResult?.output?.primaryText == "( A17 )")
        editor.save()
        let saved = try store.load()
        try #require(saved.count == 1 && saved[0].id == original.id)
        let command = try saved[0].command()
        #expect(command.run(.init(text: "next")).output?.primaryText == "(next)")
    }
}
