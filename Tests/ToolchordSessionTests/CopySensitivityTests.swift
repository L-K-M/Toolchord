import Foundation
import Testing
import ToolchordCore
@testable import ToolchordSession

/// Review G1: copies carry the result's sensitivity to the clipboard.
@MainActor
@Suite struct CopySensitivityTests {
    func makeSession(_ clipboard: MemoryClipboard) -> PaletteSession {
        let session = PaletteSession(evaluator: InlineEvaluator(), clipboard: clipboard, preferences: MemoryPreferences())
        session.activate()
        return session
    }

    @Test func generatedSecretsAreCopiedAsSecrets() async {
        let clipboard = MemoryClipboard()
        let session = makeSession(clipboard)
        session.setQuery("random string")
        await session.waitForIdle()
        #expect(session.selectedID == "random.string")
        #expect(session.copyPrimary() == .copied)
        #expect(clipboard.sensitivities == [.secret])
    }

    @Test func ordinaryResultsAndFieldsAreCopiedNormally() async {
        let clipboard = MemoryClipboard()
        let session = makeSession(clipboard)
        session.setQuery("generate uuid")
        await session.waitForIdle()
        #expect(session.selectedID == "uuid.v4")
        #expect(session.copyPrimary() == .copied)
        #expect(session.copyField("upper") == .copied)
        #expect(clipboard.sensitivities == [.normal, .normal])
    }
}
