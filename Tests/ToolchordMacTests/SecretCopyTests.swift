import AppKit
import Foundation
import SwiftUI
import Testing
import ToolchordCore
import ToolchordSession
@testable import ToolchordMac

/// Review G1: selecting part of a generated secret and pressing ⌘C must not
/// put it on the clipboard as plain text, which history apps keep and
/// Universal Clipboard shares.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SecretCopyTests {
    @Test func copyingASelectionOfASecretWritesItAsSecret() {
        let (_, textView) = CodeTextView.makeScrollable(editable: false)
        let clipboard = MemoryClipboard()
        textView.secretClipboard = clipboard
        textView.copySensitivity = .secret
        textView.string = "Xk3_9aBq-LmZ"
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.copy(nil)
        #expect(clipboard.writes == ["Xk3_"])
        #expect(clipboard.sensitivities == [.secret])

        // Nothing selected: nothing to copy.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.copy(nil)
        #expect(clipboard.writes == ["Xk3_"])
    }

    @Test(arguments: [("random", "random.string", ClipboardSensitivity.secret), ("uuid", "uuid.v4", .normal)])
    func resultViewsCopyWithTheirResultsSensitivity(query: String, commandID: String, sensitivity: ClipboardSensitivity) async throws {
        let session = PaletteSession(evaluator: BackgroundEvaluator(), clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.editDebounce = .zero
        session.activate()
        session.setQuery(query)
        session.select(commandID)
        session.openSelected()
        await session.waitForIdle()
        let hosting = NSHostingView(rootView: PaletteView(session: session, actions: InertActions(), focus: PaletteFocus()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let result = try #require(resultView(in: hosting))
        #expect(result.copySensitivity == sensitivity)
    }

    /// The read-only result text view in `view`.
    func resultView(in view: NSView) -> CodeTextView? {
        if let text = view as? CodeTextView, !text.isEditable { return text }
        return view.subviews.lazy.compactMap(resultView).first
    }
}

/// Palette actions that do nothing, for hosting the views in tests.
@MainActor
private final class InertActions: PaletteActions {
    func openSelected() {}
    func back() {}
    func escape() {}
    func copyAndClose() {}
    func copyWithoutClosing() {}
    func copyField(_ id: String) {}
    func pasteFromClipboard() {}
    func showActions(from anchor: NSView?) {}
    func regenerate() {}
    func clearInput() {}
    func openSettings() {}
}
