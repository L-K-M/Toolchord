import AppKit
import Foundation
import Testing
import ToolchordTheme
@testable import ToolchordMac

/// `color` as an opaque sRGB theme color, resolved in `appearance`.
@MainActor
private func resolved(_ color: NSColor, in appearance: NSAppearance.Name = .aqua) -> ThemeColor? {
    var result: ThemeColor?
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        result = ThemeColor(nsColor: color)
    }
    return result
}

@MainActor
@Suite struct ThemePreferencesTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ToolchordTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test func startsWithTheStandardLookAndSizes() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.theme == .standard)
        #expect(preferences.textSizes == .standard)
        #expect(preferences.customTheme == nil)
    }

    @Test func persistsTheLookAndSizesAcrossLaunches() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.apply(ThemePresets.synthwave)
        preferences.textSizes = ThemeTextSizes(codeFontSize: 15, interface: .large)

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.theme == ThemePresets.synthwave.theme)
        #expect(reloaded.textSizes == ThemeTextSizes(codeFontSize: 15, interface: .large))
        // Readable in `defaults read`.
        let stored = try #require(defaults.string(forKey: "theme"))
        #expect(stored.contains(#""appearance" : "dark""#))
        let keys = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        #expect(keys == ["theme", "codeFontSize", "interfaceTextSize"], "\(keys)")
    }

    @Test func keepsWhatItStoresSanitized() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setTheme(PaletteTheme(appearance: .system, colors: [.accent: ThemeColor(0x123456)], surfaceOpacity: 3))
        #expect(preferences.theme.colors.isEmpty)
        #expect(preferences.theme.surfaceOpacity == 1)
        preferences.textSizes.codeFontSize = 99
        #expect(preferences.textSizes.codeFontSize == 22)
    }

    @Test func damagedStoredValuesFallBack() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not json", forKey: "theme")
        defaults.set("[1, 2]", forKey: "customTheme")
        defaults.set("huge", forKey: "codeFontSize")
        defaults.set("gigantic", forKey: "interfaceTextSize")
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.theme == .standard)
        #expect(preferences.customTheme == nil)
        #expect(preferences.textSizes == .standard)

        defaults.set(99.0, forKey: "codeFontSize")
        defaults.set(#"{"appearance": "light", "cornerRadius": 400}"#, forKey: "theme")
        let clamped = AppPreferences(defaults: defaults)
        #expect(clamped.textSizes.codeFontSize == 22)
        #expect(clamped.theme == PaletteTheme(appearance: .light, cornerRadius: 28))
    }

    @Test func presetsKeepTextSizesAndTheCustomTheme() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        var custom = ThemePresets.memphis.theme
        custom[.accent] = ThemeColor(0x123456)
        preferences.setTheme(custom)
        #expect(preferences.customTheme == custom)
        preferences.textSizes = ThemeTextSizes(codeFontSize: 16, interface: .extraLarge)

        preferences.apply(ThemePresets.phosphor)
        #expect(preferences.theme == ThemePresets.phosphor.theme)
        #expect(preferences.textSizes == ThemeTextSizes(codeFontSize: 16, interface: .extraLarge))
        #expect(preferences.customTheme == custom, "trying a preset keeps the custom theme")
        #expect(AppPreferences(defaults: defaults).customTheme == custom)
    }

    @Test func resetRestoresTheStandardLookAndSizesButKeepsCustom() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let custom = PaletteTheme(appearance: .dark, colors: [.accent: ThemeColor(0xFF2E97)])
        preferences.setTheme(custom)
        preferences.textSizes = ThemeTextSizes(codeFontSize: 18, interface: .small)
        preferences.resetAppearance()
        #expect(preferences.theme == .standard)
        #expect(preferences.textSizes == .standard)
        #expect(preferences.customTheme == custom)
    }
}

@MainActor
@Suite struct PaletteStyleTests {
    @Test func standardFollowsTheSystem() {
        let style = PaletteStyle.standard
        #expect(style.appearanceName == nil)
        #expect(style.nsColor(.text) == .labelColor)
        #expect(style.nsColor(.secondaryText) == .secondaryLabelColor)
        #expect(style.nsColor(.accent) == .controlAccentColor)
        #expect(style.customAccent == nil)
        #expect(style.tint == nil)
        #expect(style.surfaceFill == nil)
        #expect(!style.showsBorders)
        // Toolchord's own colors follow light and dark.
        #expect(resolved(style.nsColor(.keys), in: .aqua) == ThemeDefaults.color(.keys, tone: .light))
        #expect(resolved(style.nsColor(.keys), in: .darkAqua) == ThemeDefaults.color(.keys, tone: .dark))
    }

    @Test func pinnedThemesPinTheirAppearance() {
        #expect(PaletteStyle(theme: ThemePresets.synthwave.theme).appearanceName == .darkAqua)
        #expect(PaletteStyle(theme: ThemePresets.memphis.theme).appearanceName == .aqua)
        #expect(PaletteStyle(theme: ThemePresets.synthwave.theme, increaseContrast: true).appearanceName == .accessibilityHighContrastDarkAqua)
        #expect(PaletteStyle(theme: ThemePresets.memphis.theme, increaseContrast: true).appearanceName == .accessibilityHighContrastAqua)
        #expect(PaletteStyle(theme: .standard, increaseContrast: true).appearanceName == nil)
    }

    @Test func customColorsAreDrawnAsSet() {
        let style = PaletteStyle(theme: ThemePresets.synthwave.theme)
        #expect(resolved(style.nsColor(.keys), in: .aqua) == ThemeColor(0x36F9F6))
        #expect(resolved(style.nsColor(.surface)) == ThemeColor(0x1A1033))
        #expect(style.customAccent != nil)
    }

    @Test func automaticCodeColorsFollowCustomText() {
        let theme = PaletteTheme(appearance: .dark, colors: [.text: ThemeColor(0xF5F0FF), .secondaryText: ThemeColor(0xC6B5E8)])
        let style = PaletteStyle(theme: theme)
        #expect(resolved(style.nsColor(.code)) == ThemeColor(0xF5F0FF))
        #expect(resolved(style.nsColor(.punctuation)) == ThemeColor(0xC6B5E8))
        #expect(resolved(style.nsColor(.comments)) == ThemeColor(0xC6B5E8))
    }

    @Test func aDrawnSurfaceTurnsOpaqueForTheAccessibilitySettings() {
        let frost = ThemePresets.frost.theme
        #expect(PaletteStyle(theme: frost).surfaceOpacity == 0.55)
        #expect(PaletteStyle(theme: frost, reduceTransparency: true).surfaceOpacity == 1)
        #expect(PaletteStyle(theme: frost, increaseContrast: true).surfaceOpacity == 1)
        // With no fill, the system material handles both settings itself.
        #expect(PaletteStyle(theme: .standard, reduceTransparency: true).surfaceOpacity == 0)
        #expect(PaletteStyle(theme: .standard, reduceTransparency: true).surfaceFill == nil)
    }

    @Test func increaseContrastRaisesToolchordsColorsAndOutlines() throws {
        let style = PaletteStyle(theme: .standard, increaseContrast: true)
        #expect(style.showsBorders)
        let keys = try #require(resolved(style.nsColor(.keys), in: .aqua))
        let well = ThemeReference.wellWash(.light).color.blended(over: ThemeReference.windowBackground(.light), opacity: ThemeReference.wellWash(.light).opacity)
        // Reading the color back rounds it to 8 bits, which can cost a hair.
        #expect(keys.contrast(with: well) >= 6.95)
    }

    @Test func aCustomAccentGetsALabelThatReads() throws {
        let lemonade = try #require(PaletteStyle(theme: ThemePresets.lemonade.theme).customAccent)
        #expect(resolved(NSColor(lemonade.label)) == .black)
        let midnight = try #require(PaletteStyle(theme: ThemePresets.midnight.theme).customAccent)
        #expect(resolved(NSColor(midnight.label)) == .black)
        let cocoa = try #require(PaletteStyle(theme: PaletteTheme(appearance: .dark, colors: [.accent: ThemeColor(0x2A1C76)])).customAccent)
        #expect(resolved(NSColor(cocoa.label)) == .white)
    }

    @Test func codeFontFallsBackToTheSystemMonospacedFont() {
        let system = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        #expect(PaletteStyle.standard.codeFont.familyName == system.familyName)
        #expect(PaletteStyle(theme: PaletteTheme(codeFontFamily: "Menlo")).codeFont.familyName == "Menlo")
        #expect(PaletteStyle(theme: PaletteTheme(codeFontFamily: "No Such Font Family")).codeFont.familyName == system.familyName)
        // A proportional family would misalign code columns.
        #expect(PaletteStyle(theme: PaletteTheme(codeFontFamily: "Helvetica")).codeFont.familyName == system.familyName)
        #expect(CodeFonts.installedFamilies().contains("Menlo"))
        #expect(!CodeFonts.installedFamilies().contains("Helvetica"))
    }

    @Test func textSizesScaleFontsAndThePanel() {
        let large = PaletteStyle(textSizes: ThemeTextSizes(codeFontSize: 16, interface: .extraLarge))
        #expect(large.panelWidth == 988)
        #expect(large.searchHeight == 598)
        #expect(large.scaled(58) == 75)
        #expect(large.codeFont.pointSize == 16)
        #expect(large.searchFont.pointSize == 26)
        #expect(large.resultHeight(lines: 1) > PaletteStyle.standard.resultHeight(lines: 1))
        #expect(PaletteStyle.standard.resultHeight(lines: 1) == 46)
        #expect(PaletteStyle.standard.resultHeight(lines: 2) == 66)
        #expect(PaletteStyle.standard.panelWidth == Theme.panelWidth)
        #expect(large.isNarrow(width: 760))
        #expect(!PaletteStyle.standard.isNarrow(width: 760))
    }

    @Test func theListKeepsItsShareOfTheWidth() {
        #expect(PaletteStyle.standard.listWidth(forPanelWidth: 760) == 300)
        #expect(PaletteStyle.standard.listWidth(forPanelWidth: 600) == 237)
        #expect(PaletteStyle.standard.radius(10) == 10)
        #expect(PaletteStyle(theme: PaletteTheme(cornerRadius: 9)).radius(10) == 5)
    }
}

@MainActor
@Suite struct ThemedCodeViewTests {
    @Test func tokensTakeTheThemeColorsAndFont() throws {
        let style = PaletteStyle(theme: ThemePresets.synthwave.theme)
        let text = SyntaxHighlighter.attributedString(for: #"{"a": 1, "b": true}"#, syntax: .json, style: style)
        let key = try #require(text.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor)
        let number = try #require(text.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor)
        let literal = try #require(text.attribute(.foregroundColor, at: 15, effectiveRange: nil) as? NSColor)
        #expect(resolved(key) == ThemeColor(0x36F9F6))
        #expect(resolved(number) == ThemeColor(0xFF9E64))
        #expect(resolved(literal) == ThemeColor(0xC792EA))
        #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == style.codeFont)
    }

    @Test func anEditorTakesANewStyleWithoutLosingItsText() {
        let (_, textView) = CodeTextView.makeScrollable(.editor, style: .standard)
        textView.string = "{\"a\": 1}"
        let larger = PaletteStyle(theme: PaletteTheme(appearance: .dark, colors: [.code: ThemeColor(0xB6FFC4)]), textSizes: ThemeTextSizes(codeFontSize: 16, interface: .standard))
        textView.apply(larger)
        #expect(textView.string == "{\"a\": 1}")
        #expect(textView.font?.pointSize == 16)
        #expect(resolved(textView.textColor ?? .clear) == ThemeColor(0xB6FFC4))
        #expect(textView.appliedStyle == larger)
    }

    @Test func aResultLeavesItsTokenColorsToItsOwner() throws {
        let (_, textView) = CodeTextView.makeScrollable(.result, style: .standard)
        let coordinator = ResultTextView.Coordinator()
        let synthwave = PaletteStyle(theme: ThemePresets.synthwave.theme)
        coordinator.show(#"{"a": 1}"#, syntax: .json, style: .standard, identity: "json.format", in: textView)
        textView.apply(synthwave)
        coordinator.show(#"{"a": 1}"#, syntax: .json, style: synthwave, identity: "json.format", in: textView)
        let key = try #require(textView.textStorage?.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor)
        #expect(resolved(key) == ThemeColor(0x36F9F6))
    }

    @Test func previewCodeViewsNeverTakeFocus() {
        let (_, textView) = CodeTextView.makeScrollable(.result, style: .standard)
        #expect(textView.acceptsFirstResponder)
        textView.refusesFocus = true
        #expect(!textView.acceptsFirstResponder)
    }
}
