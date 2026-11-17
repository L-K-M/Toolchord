import Testing
@testable import ToolchordTheme

@Suite struct ThemeAuditTests {
    @Test func toolchordsOwnDefaultsPassInBothTones() {
        #expect(ThemeAudit.issues(in: .standard, tone: .light).isEmpty)
        #expect(ThemeAudit.issues(in: .standard, tone: .dark).isEmpty)
        // A pinned theme with no colors of its own draws the same defaults.
        #expect(ThemeAudit.issues(in: PaletteTheme(appearance: .light)).isEmpty)
        #expect(ThemeAudit.issues(in: PaletteTheme(appearance: .dark)).isEmpty)
    }

    @Test func systemColorsAreNotChecked() {
        // The system draws text and accent; Toolchord can't change them.
        for role in [ThemeColorRole.accent, .text, .secondaryText, .code, .punctuation, .comments] {
            #expect(ThemeAudit.checkedColor(role, in: .standard, tone: .light) == nil, "\(role)")
        }
    }

    @Test func reportsAColorOnceAgainstItsWorstBackground() throws {
        let theme = PaletteTheme(appearance: .light, colors: [.surface: ThemeColor(0xFFFFFF), .well: ThemeColor(0xEEEEEE), .strings: ThemeColor(0xAAAAAA)], surfaceOpacity: 1)
        let issues = ThemeAudit.issues(in: theme)
        #expect(issues.map(\.role) == [.strings])
        let issue = try #require(issues.first)
        #expect(issue.background == ThemeColor(0xEEEEEE))
        #expect(issue.tone == .light)
        #expect(issue.minimum == 4.5)
        #expect(issue.ratio < 2.2)
        #expect(issue.summary == "Strings: 2.0:1, needs 4.5:1")
    }

    @Test func textIsCheckedOnTheSelectionToo() {
        // Light text on a dark theme survives the panel but not a bright accent wash.
        let theme = PaletteTheme(appearance: .dark, colors: [
            .surface: ThemeColor(0x202020), .well: ThemeColor(0x202020), .text: ThemeColor(0xA0A0A0), .accent: ThemeColor(0xFFFFFF),
        ], surfaceOpacity: 1)
        #expect(ThemeAudit.issues(in: theme).map(\.role) == [.text])
        var calmer = theme
        calmer[.accent] = ThemeColor(0x3A6EA5)
        #expect(ThemeAudit.issues(in: calmer).isEmpty)
    }

    @Test func translucentPanelsAreCheckedOverGlassAndOpaque() throws {
        // Over the dark glass, Toolchord's pale failure color reads; once
        // Reduce Transparency shows the mid-gray surface, it doesn't.
        let theme = PaletteTheme(appearance: .dark, colors: [.surface: ThemeColor(0x6A6A6A)], surfaceOpacity: 0.2)
        let failure = try #require(ThemeAudit.issues(in: theme).first { $0.role == .failure })
        #expect(failure.background.relativeLuminance > 0.1)
        // With no fill, Reduce Transparency shows the system's dark material.
        var glassOnly = theme
        glassOnly.surfaceOpacity = 0
        #expect(ThemeAudit.issues(in: glassOnly).isEmpty)
    }

    @Test func punctuationAndTheAccentNeedLess() {
        let theme = PaletteTheme(appearance: .light, colors: [
            .surface: ThemeColor(0xFFFFFF), .well: ThemeColor(0xFFFFFF), .punctuation: ThemeColor(0x8A8A8A), .accent: ThemeColor(0x8A8A8A),
        ], surfaceOpacity: 1)
        // #8A8A8A on white is about 3.4:1: enough for glyphs, not for text.
        #expect(ThemeAudit.issues(in: theme).isEmpty)
        var asText = theme
        asText[.strings] = ThemeColor(0x8A8A8A)
        #expect(ThemeAudit.issues(in: asText).map(\.role) == [.strings])
    }

    @Test func automaticColorsAreCheckedOnCustomSurfaces() {
        // Toolchord's default dark-mode syntax colors are pale; on a pale
        // custom well they fail, and the audit says so.
        let theme = PaletteTheme(appearance: .dark, colors: [.surface: ThemeColor(0x1E1E1E), .well: ThemeColor(0x9A9A9A)], surfaceOpacity: 1)
        let roles = Set(ThemeAudit.issues(in: theme).map(\.role))
        #expect(roles.isSuperset(of: [.keys, .strings, .numbers, .literals]))
    }

    @Test func automaticTextIsCheckedOnTheThemesOwnBackgrounds() {
        // Black wells in the Light appearance: the system's dark label
        // colors would vanish on them, though every custom color passes.
        let gray = ThemeColor(0x767676)
        var colors: [ThemeColorRole: ThemeColor] = [.surface: .white, .well: .black]
        for role in [ThemeColorRole.keys, .strings, .numbers, .literals, .punctuation, .comments, .success, .warning, .failure] {
            colors[role] = gray
        }
        let theme = PaletteTheme(appearance: .light, colors: colors, surfaceOpacity: 1)
        let issues = ThemeAudit.issues(in: theme)
        #expect(Set(issues.map(\.role)) == [.text, .secondaryText])
        #expect(issues.allSatisfy { $0.ratio < 1.1 }, "translucent black vanishes on black")
        // Raising makes them custom colors. No color reads at 4.5:1 on a
        // white panel, black wells, and the light selection at once, so
        // raising gets as close as it can instead of picking black or white.
        let raised = ThemeAudit.raisingContrast(of: theme)
        #expect(raised[.text] != nil && raised[.secondaryText] != nil)
        #expect(ThemeAudit.issues(in: raised).allSatisfy { $0.ratio > 3.5 }, "\(ThemeAudit.issues(in: raised))")
        // On wells that agree with the appearance, the same colors pass.
        var agreeing = theme
        agreeing[.well] = ThemeColor(0xF2F2F2)
        for role in [ThemeColorRole.keys, .strings, .numbers, .literals, .comments, .success, .warning, .failure] {
            agreeing[role] = ThemeColor(0x5C5C5C)
        }
        #expect(ThemeAudit.issues(in: agreeing).isEmpty, "\(ThemeAudit.issues(in: agreeing))")
        // System text on system backgrounds stays the system's business.
        #expect(!ThemeAudit.drawsOwnBackground(PaletteTheme(appearance: .light, surfaceOpacity: 0.6)))
        #expect(!ThemeAudit.drawsOwnBackground(PaletteTheme(appearance: .light, colors: [.surface: .white])))
    }

    @Test func flagsAPanelThatDisagreesWithTheAppearance() {
        let lightOnDark = PaletteTheme(appearance: .dark, colors: [.surface: ThemeColor(0xFAFAFA)], surfaceOpacity: 1)
        #expect(ThemeAudit.problems(in: lightOnDark).count == 1)
        let darkOnLight = PaletteTheme(appearance: .light, colors: [.surface: ThemeColor(0x101010)], surfaceOpacity: 1)
        #expect(ThemeAudit.problems(in: darkOnLight).count == 1)
        // At zero opacity the surface color isn't drawn, so it can't clash...
        let undrawn = PaletteTheme(appearance: .dark, colors: [.surface: ThemeColor(0xFAFAFA)], surfaceOpacity: 0)
        #expect(ThemeAudit.problems(in: undrawn).isEmpty)
        // ...and custom colors under the system appearance are a problem of their own.
        #expect(ThemeAudit.problems(in: PaletteTheme(colors: [.accent: ThemeColor(0x123456)])).count == 1)
    }

    @Test func raisingContrastFixesEveryIssueAndKeepsPassingColors() {
        let theme = PaletteTheme(appearance: .light, colors: [
            .surface: ThemeColor(0xFFF8E7), .well: ThemeColor(0xFFF0CC), .accent: ThemeColor(0xFFD84D),
            .text: ThemeColor(0x9C8F70), .keys: ThemeColor(0xE8A23A), .strings: ThemeColor(0x2E6B2E),
        ], surfaceOpacity: 1)
        let before = ThemeAudit.issues(in: theme)
        #expect(Set(before.map(\.role)).isSuperset(of: [.accent, .text, .keys]))
        let raised = ThemeAudit.raisingContrast(of: theme)
        #expect(ThemeAudit.issues(in: raised).isEmpty, "\(ThemeAudit.issues(in: raised))")
        #expect(raised[.strings] == ThemeColor(0x2E6B2E))
        #expect(raised[.surface] == theme[.surface])
        // Stored colors stay 8-bit, so the fixed theme survives a round trip.
        #expect(PaletteTheme(storedText: raised.jsonText) == raised)
    }

    @Test func raisingContrastLeavesTheSystemAppearanceAlone() {
        #expect(ThemeAudit.raisingContrast(of: .standard) == .standard)
    }

    @Test func increasedContrastRaisesCustomAndDefaultColors() {
        let drawn = ThemeAudit.drawnColors(for: .standard, tone: .light, increasedContrast: true)
        let normal = ThemeAudit.drawnColors(for: .standard, tone: .light, increasedContrast: false)
        #expect(normal[.keys] == ThemeDefaults.color(.keys, tone: .light))
        #expect(drawn[.keys] != normal[.keys])
        #expect(drawn[.text] == nil, "the system raises its own label colors")
        #expect(drawn[.accent] == nil)
        let synthwave = ThemeAudit.drawnColors(for: ThemePresets.synthwave.theme, tone: .dark, increasedContrast: true)
        #expect(synthwave[.surface] == ThemePresets.synthwave.theme[.surface], "backgrounds keep their color")
        #expect((synthwave[.comments]?.contrast(with: ThemePresets.synthwave.theme[.well]!) ?? 0) >= 7)
    }
}
