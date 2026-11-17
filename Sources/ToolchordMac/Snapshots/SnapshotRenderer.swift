import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession
import ToolchordTheme

/// Renders palette states to PNG for design review and documentation.
///
/// Window materials (glass and vibrancy) are composited by the window server
/// and do not appear in offscreen captures, so snapshots draw an opaque
/// stand-in of similar tone: `ThemeReference.glass`, which the contrast
/// audit measures against too. A theme's surface is drawn over it.
@MainActor
public enum SnapshotRenderer {
    public struct Scenario: Sendable {
        public let name: String
        /// The appearance for the standard theme; a pinned theme uses its own.
        public let appearance: NSAppearance.Name
        /// The panel width at the standard text size.
        public let width: CGFloat
        let theme: PaletteTheme
        let textSizes: ThemeTextSizes
        /// Draws as with Increase Contrast, which turns on Reduce Transparency.
        let increaseContrast: Bool
        let setUp: @MainActor @Sendable (PaletteSession) async -> Void

        init(
            name: String,
            appearance: NSAppearance.Name,
            width: CGFloat,
            theme: PaletteTheme = .standard,
            textSizes: ThemeTextSizes = .standard,
            increaseContrast: Bool = false,
            setUp: @escaping @MainActor @Sendable (PaletteSession) async -> Void
        ) {
            self.name = name
            self.appearance = appearance
            self.width = width
            self.theme = theme
            self.textSizes = textSizes
            self.increaseContrast = increaseContrast
            self.setUp = setUp
        }
    }

    private static let sampleJSON = #"{"requestId":"req_81f2","status":200,"cache":"HIT","items":[1,2.50,-0],"ok":true}"#

    /// One search-mode snapshot per preset, in its own appearance.
    private static let presetScenarios: [Scenario] = ThemePresets.all.dropFirst().map { preset in
        Scenario(name: "theme-\(preset.id)", appearance: .aqua, width: Theme.panelWidth, theme: preset.theme) { session in
            session.attach(sampleJSON)
        }
    }

    /// Text sizes, a tool in a preset with its own code font, the status
    /// colors, and the accessibility treatments.
    private static let themeEdgeScenarios: [Scenario] = [
        Scenario(name: "theme-default-extra-large-text", appearance: .darkAqua, width: Theme.panelWidth,
                 textSizes: ThemeTextSizes(codeFontSize: 16, interface: .extraLarge)) { session in
            session.attach(sampleJSON)
        },
        Scenario(name: "theme-default-small-text", appearance: .aqua, width: Theme.panelWidth,
                 textSizes: ThemeTextSizes(codeFontSize: 10, interface: .small)) { session in
            session.attach(sampleJSON)
        },
        Scenario(name: "theme-phosphor-tool", appearance: .aqua, width: Theme.panelWidth, theme: ThemePresets.phosphor.theme) { session in
            session.attach(#"<feed><!-- note --><entry id="42">Release</entry></feed>"#)
            session.openSelected()
        },
        Scenario(name: "theme-memphis-jwt-warnings", appearance: .aqua, width: Theme.panelWidth, theme: ThemePresets.memphis.theme) { session in
            session.setQuery("jwt")
            session.attach("Bearer eyJhbGciOiJub25lIn0.eyJleHAiOjAsIm5iZiI6NDEwMjQ0NDgwMH0.")
        },
        Scenario(name: "theme-lemonade-invalid", appearance: .aqua, width: Theme.panelWidth, theme: ThemePresets.lemonade.theme) { session in
            session.attach("{\n  \"status\": 200,\n  \"cache\": HIT\n}")
        },
        Scenario(name: "theme-default-increased-contrast", appearance: .aqua, width: Theme.panelWidth, increaseContrast: true) { session in
            session.attach(sampleJSON)
        },
        Scenario(name: "theme-synthwave-increased-contrast", appearance: .aqua, width: Theme.panelWidth,
                 theme: ThemePresets.synthwave.theme, increaseContrast: true) { session in
            session.attach(sampleJSON)
        },
        Scenario(name: "theme-frost-increased-contrast", appearance: .aqua, width: Theme.panelWidth,
                 theme: ThemePresets.frost.theme, increaseContrast: true) { session in
            session.attach(sampleJSON)
        },
        Scenario(name: "search-color-translucent", appearance: .darkAqua, width: Theme.panelWidth) { session in
            session.attach("#ff880080")
        },
    ]

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
    ] + presetScenarios + themeEdgeScenarios

    /// The Settings ▸ Appearance tab in a theme, for reviewing the editor's
    /// layout. The preview's glass doesn't show in offscreen captures.
    private static let settingsScenarios: [(name: String, theme: PaletteTheme, appearance: NSAppearance.Name)] = [
        ("settings-appearance-default", .standard, .aqua),
        ("settings-appearance-synthwave", ThemePresets.synthwave.theme, .darkAqua),
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
        for scenario in settingsScenarios where names.isEmpty || names.contains(scenario.name) {
            let url = directory.appendingPathComponent("\(scenario.name).png")
            try await renderAppearanceSettings(theme: scenario.theme, appearance: scenario.appearance, to: url)
            urls.append(url)
        }
        return urls
    }

    static func renderAppearanceSettings(theme: PaletteTheme, appearance: NSAppearance.Name, to url: URL) async throws {
        // Throwaway preferences and a private pasteboard: rendering must not
        // touch the person's settings or clipboard.
        let suite = "ch.lkmc.Toolchord.snapshots.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileWriteUnknown) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setTheme(theme)
        let clipboard = SystemClipboard(pasteboard: NSPasteboard(name: NSPasteboard.Name("ch.lkmc.Toolchord.snapshots")))
        let hosting = NSHostingView(rootView: AppearanceSettingsView(preferences: preferences, clipboard: clipboard))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        // Let the preview's demo session evaluate and SwiftUI settle.
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        window.close()
    }

    static func render(_ scenario: Scenario, to url: URL) async throws {
        let session = PaletteSession.demo()
        await scenario.setUp(session)
        await session.waitForIdle()

        let style = PaletteStyle(
            theme: scenario.theme,
            textSizes: scenario.textSizes,
            increaseContrast: scenario.increaseContrast,
            reduceTransparency: scenario.increaseContrast
        )
        let appearanceName = style.appearanceName ?? scenario.appearance
        let tone: ThemeTone = scenario.theme.appearance.pinnedTone ?? (scenario.appearance == .darkAqua ? .dark : .light)
        let width = style.scaled(scenario.width)
        let height = session.isInTool ? style.toolHeight : style.searchHeight
        let size = NSSize(width: width, height: height)
        let focus = PaletteFocus()
        let view = PaletteView(
            session: session,
            actions: InertPaletteActions(),
            focus: focus,
            isNarrow: style.isNarrow(width: width),
            listWidth: style.listWidth(forPanelWidth: width),
            style: style
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let background = NSView(frame: hosting.frame)
        background.wantsLayer = true
        background.addSubview(hosting)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = background
        background.layer?.backgroundColor = NSColor(theme: ThemeReference.glass(tone)).cgColor
        background.layer?.cornerRadius = style.cornerRadius
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
}
