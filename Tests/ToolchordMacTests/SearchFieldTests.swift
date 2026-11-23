import AppKit
import SwiftUI
import Testing
import ToolchordSession
@testable import ToolchordMac

@MainActor
@Suite struct SearchFieldTests {
    @Test func previewSearchFieldRefusesKeyboardFocus() {
        let field = SearchTextField()
        #expect(field.acceptsFirstResponder)
        field.refusesFirstResponder = true
        #expect(!field.acceptsFirstResponder)
    }

    @Test func searchExposesItsQueryAndCurrentMatchSeparately() async throws {
        let session = PaletteSession(clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.activate()
        let focus = PaletteFocus()
        let view = SearchField(session: session, focus: focus, onOpen: {}, onEscape: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        defer { window.close() }

        for (query, selection) in [("format json", "Format JSON"), ("zzzzzzzzzzz", "No tools found")] {
            session.setQuery(query)
            for _ in 0..<10 {
                window.contentView?.layoutSubtreeIfNeeded()
                if focus.searchField?.stringValue == query { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let field = try #require(focus.searchField)
            let accessibleValue: Any? = field.accessibilityValue()
            #expect(accessibleValue as? String == query)
            let hint = try #require(field.accessibilityHelp())
            #expect(hint.contains(selection))
            #expect(field.accessibilityValueDescription() != "Format JSON")
            if session.selectedCommand == nil {
                #expect(!hint.contains("Format JSON"))
            }
            #expect(field.focusRingType == .exterior)
        }
    }
}
