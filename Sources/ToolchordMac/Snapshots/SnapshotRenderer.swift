import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession

/// Renders palette states to PNG for design review and documentation.
///
/// Window materials (glass and vibrancy) are composited by the window server
/// and do not appear in offscreen captures, so snapshots draw an opaque
/// stand-in background of similar tone.
@MainActor
public enum SnapshotRenderer {
    public struct Scenario: Sendable {
        public let name: String
        public let appearance: NSAppearance.Name
        public let width: CGFloat
        let setUp: @MainActor @Sendable (PaletteSession) async -> Void
    }

    public static let scenarios: [Scenario] = [
        Scenario(name: "search-empty", appearance: .aqua, width: Theme.panelWidth) { _ in },
        Scenario(name: "search-json", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach(#"{"requestId":"req_81f2","status":200,"cache":"HIT","items":[1,2.50,-0]}"#)
        },
        Scenario(name: "search-json-light", appearance: .aqua, width: Theme.panelWidth) { session in
            session.attach(#"{"requestId":"req_81f2","status":200,"cache":"HIT","items":[1,2.50,-0]}"#)
        },
        Scenario(name: "search-json-invalid", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("{\n  \"status\": 200,\n  \"cache\": HIT\n}")
        },
        Scenario(name: "search-jwt", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")
        },
        Scenario(name: "search-jwt-warnings", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.setQuery("jwt")
            session.attach("Bearer eyJhbGciOiJub25lIn0.eyJleHAiOjAsIm5iZiI6NDEwMjQ0NDgwMH0.")
        },
        Scenario(name: "search-url", appearance: .aqua, width: Theme.panelWidth) { session in
            session.attach("https://example.test/search?q=tool+chord&lang=en&lang=de&page=2#results")
        },
        Scenario(name: "search-query-uuid", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach(#"{"a":1}"#)
            session.setQuery("guid")
        },
        Scenario(name: "search-timestamp", appearance: .aqua, width: Theme.panelWidth) { session in
            session.attach("1700000000")
        },
        // Boundary coverage for option-heavy commands and narrow panels.

        Scenario(name: "search-number-options", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("42")
            session.select("number.hex")
        },
        Scenario(name: "tool-number-options", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("42")
            session.select("number.hex")
            session.openSelected()
        },
        Scenario(name: "tool-number-options-narrow", appearance: .darkAqua, width: 600) { session in
            session.attach("42")
            session.select("number.hex")
            session.openSelected()
        },
        Scenario(name: "search-random-options", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.setQuery("random")
            session.select("random.string")
        },
        Scenario(name: "tool-random-options", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.setQuery("random")
            session.select("random.string")
            session.openSelected()
        },
        Scenario(name: "tool-random-options-narrow", appearance: .darkAqua, width: 600) { session in
            session.setQuery("random")
            session.select("random.string")
            session.openSelected()
        },

        Scenario(name: "search-color", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("#ff8800")
        },
        Scenario(name: "tool-json", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach(#"{"requestId":"req_81f2","status":200,"cache":"HIT"}"#)
            session.openSelected()
        },
        Scenario(name: "tool-uuid", appearance: .aqua, width: Theme.panelWidth) { session in
            session.setQuery("uuid")
            session.openSelected()
        },
        Scenario(name: "search-narrow", appearance: .aqua, width: 600) { session in
            session.attach("Hello, World")
        },
        Scenario(name: "search-markdown", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("## Release notes\n\nToolchord now converts **Markdown** and HTML.\n\n- Render Markdown to HTML\n- [Docs](https://example.test/docs) and `code`\n")
        },
        Scenario(name: "search-html", appearance: .aqua, width: Theme.panelWidth) { session in
            session.attach("<article><h2>Release notes</h2><p>Toolchord now converts <b>Markdown</b> and HTML.</p><ul><li>Render Markdown</li><li><a href=\"https://example.test/docs\">Docs</a></li></ul></article>")
        },
        Scenario(name: "search-plaintext", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("curl\u{00A0}\u{2014}silent \u{201C}https://example.test/api?q=1\u{201D}\u{200B}")
        },

    ]

    /// Writes one PNG per scenario into `directory` and returns their URLs.
    public static func renderAll(to directory: URL, only names: Set<String> = []) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for scenario in scenarios where names.isEmpty || names.contains(scenario.name) {
            let url = directory.appendingPathComponent("\(scenario.name).png")
            try await render(scenario, to: url)
            urls.append(url)
        }
        return urls
    }

    static func render(_ scenario: Scenario, to url: URL) async throws {
        let preferences = MemoryPreferences(overrides: [:], recentCommandIDs: [])
        let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
        let session = PaletteSession(
            clipboard: MemoryClipboard(),
            preferences: preferences,
            clock: clock,
            timeZone: { TimeZone(identifier: "Europe/Zurich")! }
        )
        session.activate()
        await scenario.setUp(session)
        await session.waitForIdle()

        let height = session.isInTool ? Theme.toolHeight : Theme.searchHeight
        let size = NSSize(width: scenario.width, height: height)
        let focus = PaletteFocus()
        let view = PaletteView(session: session, actions: NoActions(), focus: focus, isNarrow: scenario.width < Theme.narrowWidth)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let background = NSView(frame: hosting.frame)
        background.wantsLayer = true
        background.addSubview(hosting)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scenario.appearance)
        window.contentView = background
        background.layer?.backgroundColor = standInBackground(for: scenario.appearance).cgColor
        background.layer?.cornerRadius = Theme.cornerRadius
        window.layoutIfNeeded()
        // Let SwiftUI settle layout and lazy content.
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }

        guard let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        background.cacheDisplay(in: background.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        window.close()
    }

    private static func standInBackground(for appearance: NSAppearance.Name) -> NSColor {
        appearance == .darkAqua
            ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    }

    @MainActor
    private final class NoActions: PaletteActions {
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
}
