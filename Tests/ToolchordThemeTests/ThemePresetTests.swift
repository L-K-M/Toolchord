import Testing
@testable import ToolchordTheme

@Suite struct ThemePresetTests {
    @Test func shipsDefaultFirstAndAtLeastSixteenMore() {
        #expect(ThemePresets.all.first == ThemePresets.standard)
        #expect(ThemePresets.standard.theme == .standard)
        #expect(ThemePresets.all.count >= 17)
    }

    @Test func idsAndNamesAreUnique() {
        #expect(Set(ThemePresets.all.map(\.id)).count == ThemePresets.all.count)
        #expect(Set(ThemePresets.all.map(\.name)).count == ThemePresets.all.count)
        for preset in ThemePresets.all {
            #expect(!preset.name.isEmpty && !preset.tagline.isEmpty, "\(preset.id)")
            #expect(ThemePresets.preset(id: preset.id) == preset)
        }
        #expect(ThemePresets.preset(id: "nope") == nil)
    }

    @Test func idsStayStable() {
        // Snapshot file names use these; renaming one is a visible change.
        #expect(ThemePresets.all.map(\.id) == [
            "default", "memphis", "paper", "newsprint", "bubblegum", "lemonade", "peppermint", "matcha", "vaporwave", "frost",
            "synthwave", "phosphor", "amber", "midnight", "halloween", "lagoon", "aurora", "cosmic", "cocoa", "smoke", "highContrast",
        ])
    }

    @Test func everyLookIsDistinctAndAlreadySanitized() {
        #expect(Set(ThemePresets.all.map(\.theme)).count == ThemePresets.all.count)
        for preset in ThemePresets.all {
            #expect(preset.theme.sanitized == preset.theme, "\(preset.id)")
        }
    }

    @Test func onlyDefaultFollowsTheSystem() {
        for preset in ThemePresets.all.dropFirst() {
            #expect(preset.theme.appearance != .system, "\(preset.id)")
            #expect(!preset.theme.colors.isEmpty, "\(preset.id)")
        }
        let tones = ThemePresets.all.compactMap(\.theme.appearance.pinnedTone)
        #expect(tones.filter { $0 == .light }.count >= 8)
        #expect(tones.filter { $0 == .dark }.count >= 8)
    }

    @Test func presetsNameOnlyFontsEveryMacShips() {
        for preset in ThemePresets.all {
            if let family = preset.theme.codeFontFamily {
                #expect(ThemePresets.shippedCodeFonts.contains(family), "\(preset.id): \(family)")
            }
        }
    }

    @Test func aThemeIsRecognizedByItsValues() throws {
        let memphis = ThemePresets.memphis
        #expect(ThemePresets.matching(memphis.theme) == memphis)
        var edited = memphis.theme
        edited[.accent] = ThemeColor(0x123456)
        #expect(ThemePresets.matching(edited) == nil)
        edited[.accent] = memphis.theme[.accent]
        #expect(ThemePresets.matching(edited) == memphis)
        // A slider dragged back to the preset's value counts too.
        edited.surfaceOpacity = 0.99999
        #expect(ThemePresets.matching(edited) == memphis)
        #expect(ThemePresets.matching(.standard) == ThemePresets.standard)
        // A system theme that kept colors before sanitizing is still Default.
        #expect(ThemePresets.matching(PaletteTheme(colors: [.accent: ThemeColor(0x123456)])) == ThemePresets.standard)
    }

    @Test func everyPresetPassesTheContrastAudit() {
        for preset in ThemePresets.all {
            #expect(ThemeAudit.issues(in: preset.theme).isEmpty, "\(preset.id): \(ThemeAudit.issues(in: preset.theme))")
            #expect(ThemeAudit.problems(in: preset.theme).isEmpty, "\(preset.id): \(ThemeAudit.problems(in: preset.theme))")
        }
    }

    @Test func everyPresetReachesIncreasedContrast() {
        for preset in ThemePresets.all {
            for tone in preset.theme.tones {
                let drawn = ThemeAudit.drawnColors(for: preset.theme, tone: tone, increasedContrast: true)
                var raised = preset.theme
                raised.appearance = tone == .light ? .light : .dark
                for (role, color) in drawn where role.kind != .background { raised[role] = color }
                let backdrop = ThemeAudit.Backdrop(theme: raised, tone: tone, increasedContrast: true, accent: raised[.accent])
                for (role, color) in drawn {
                    guard let minimum = ThemeAudit.minimum(for: role.kind, increasedContrast: true) else { continue }
                    #expect(color.worstContrast(against: backdrop.backgrounds(for: role)) >= minimum - 1e-9, "\(preset.id) \(tone) \(role)")
                }
            }
        }
    }
}
