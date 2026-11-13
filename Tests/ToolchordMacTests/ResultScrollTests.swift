import AppKit
import Foundation
import SwiftUI
import Testing
import ToolchordCore
import ToolchordSession
@testable import ToolchordMac

/// Review U2: editing the input of an open tool must not throw the result
/// back to its first line, while new input or another command starts at the top.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ResultScrollTests {
    /// A JSON array of `count` numbers from `start`; Format JSON puts each on its own line.
    func document(_ count: Int, from start: Int = 1) -> String {
        "[" + (start..<(start + count)).map(String.init).joined(separator: ",") + "]"
    }

    /// The palette in an offscreen window with `text` attached and `query`
    /// typed, optionally with the selected tool open, and its result shown.
    func openPalette(_ text: String, query: String, openTool: Bool, evaluator: HeldEvaluator) async throws -> (NSWindow, PaletteSession) {
        let session = PaletteSession(evaluator: evaluator, clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.editDebounce = .zero
        session.activate()
        session.setQuery(query)
        session.attach(text)
        if openTool { session.openSelected() }
        await evaluator.release(count: 1)
        await session.waitForIdle()
        let hosting = NSHostingView(rootView: PaletteView(session: session, actions: InertActions(), focus: PaletteFocus()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        try await settle(window)
        return (window, session)
    }

    /// Lets SwiftUI and TextKit finish layout.
    func settle(_ window: NSWindow) async throws {
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    /// The read-only result text view on screen.
    func resultView(in window: NSWindow) -> CodeTextView? {
        func search(_ view: NSView) -> CodeTextView? {
            if let text = view as? CodeTextView, !text.isEditable { return text }
            return view.subviews.lazy.compactMap(search).first
        }
        return window.contentView.flatMap(search)
    }

    @Test func editsKeepTheResultScrollPosition() async throws {
        let evaluator = HeldEvaluator()
        let (window, session) = try await openPalette(document(400), query: "format json", openTool: true, evaluator: evaluator)
        defer { window.close() }
        let result = try #require(resultView(in: window))
        result.scroll(NSPoint(x: 0, y: 900))
        try await settle(window)
        let position = result.visibleRect.minY
        #expect(position > 0, "The result should be long enough to scroll")

        // While the edit is evaluated, the previous result stays, dimmed, in place.
        session.editInput(document(401))
        await evaluator.waitForHeld(1)
        try await settle(window)
        #expect(resultView(in: window) === result, "The pending state should update the result view, not replace it")
        #expect(result.visibleRect.minY == position)

        await evaluator.release(count: 1)
        await session.waitForIdle()
        try await settle(window)
        #expect(resultView(in: window) === result, "The new result should update the result view, not replace it")
        #expect(result.string.hasSuffix("401\n]"))
        #expect(result.visibleRect.minY == position)
    }

    @Test func aNewPasteStartsAtTheTop() async throws {
        let evaluator = HeldEvaluator()
        let (window, session) = try await openPalette(document(400), query: "format json", openTool: false, evaluator: evaluator)
        defer { window.close() }
        let result = try #require(resultView(in: window))
        result.scroll(NSPoint(x: 0, y: 900))
        try await settle(window)
        #expect(result.visibleRect.minY > 0)

        session.attach(document(400, from: 2))
        await evaluator.release(count: 1)
        await session.waitForIdle()
        try await settle(window)
        let shown = try #require(resultView(in: window))
        #expect(shown.string.hasPrefix("[\n  2,"))
        #expect(shown.visibleRect.minY == 0)
    }

    @Test func aDifferentCommandStartsAtTheTop() async throws {
        let evaluator = HeldEvaluator()
        let (window, session) = try await openPalette(document(400), query: "format json", openTool: true, evaluator: evaluator)
        defer { window.close() }
        let result = try #require(resultView(in: window))
        result.scroll(NSPoint(x: 0, y: 900))
        try await settle(window)
        #expect(result.visibleRect.minY > 0)

        session.back()
        session.setQuery("validate json")
        #expect(session.selectedID == "json.validate")
        session.openSelected()
        await evaluator.release(count: 1)
        await session.waitForIdle()
        try await settle(window)
        let shown = try #require(resultView(in: window))
        #expect(shown.string.hasPrefix("[1,2,3"))
        #expect(shown.visibleRect.minY == 0)
    }

    @Test func aNewIdentityStartsAtTheTopEvenWithTheSameText() async throws {
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        defer { window.close() }
        let coordinator = ResultTextView.Coordinator()
        let text = (1...400).map { "line \($0)" }.joined(separator: "\n")

        coordinator.show(text, syntax: .plain, identity: "json.minify", in: textView)
        try await settle(window)
        textView.scroll(NSPoint(x: 0, y: 900))
        try await settle(window)
        let position = textView.visibleRect.minY
        #expect(position > 0)

        coordinator.show(text, syntax: .plain, identity: "json.minify", in: textView)
        #expect(textView.visibleRect.minY == position)
        coordinator.show(text, syntax: .plain, identity: "json.validate", in: textView)
        #expect(textView.visibleRect.minY == 0)
    }
}

/// Holds every evaluation until the test releases it, so the pending state is
/// on screen for as long as the test needs.
actor HeldEvaluator: ToolEvaluating {
    private var held: [CheckedContinuation<Void, Never>] = []

    func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult {
        await withCheckedContinuation { held.append($0) }
        return command.run(request)
    }

    func waitForHeld(_ count: Int) async {
        while held.count < count { await Task.yield() }
    }

    /// Waits until `count` evaluations are held, then lets them finish.
    func release(count: Int) async {
        await waitForHeld(count)
        let released = held.prefix(count)
        held.removeFirst(count)
        for item in released { item.resume() }
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
