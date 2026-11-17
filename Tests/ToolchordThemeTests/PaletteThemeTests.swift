import Foundation
import Testing
@testable import ToolchordTheme

@Suite struct PaletteThemeTests {
    @Test func standardIsThePaletteBeforeThemes() {
        let standard = PaletteTheme.standard
        #expect(standard.appearance == .system)
        #expect(standard.colors.isEmpty)
        #expect(standard.surfaceOpacity == 0)
        #expect(standard.cornerRadius == 18)
        #expect(standard.codeFontFamily == nil)
        #expect(standard.sanitized == standard)
        #expect(standard.tones == [.light, .dark])
        #expect(PaletteTheme(appearance: .dark).tones == [.dark])
    }

    @Test func systemAppearanceDropsCustomColors() {
        let theme = PaletteTheme(appearance: .system, colors: [.accent: ThemeColor(0xFF2E97)])
        #expect(theme.sanitized.colors.isEmpty)
        let pinned = PaletteTheme(appearance: .dark, colors: [.accent: ThemeColor(0xFF2E97)])
        #expect(pinned.sanitized.colors == [.accent: ThemeColor(0xFF2E97)])
    }

    @Test func sanitizingClampsAndRoundsNumbers() {
        var theme = PaletteTheme(appearance: .light, surfaceOpacity: 1.7, cornerRadius: -4)
        #expect(theme.sanitized.surfaceOpacity == 1)
        #expect(theme.sanitized.cornerRadius == 0)
        theme.surfaceOpacity = 0.55000000000000004
        theme.cornerRadius = 13.6
        #expect(theme.sanitized.surfaceOpacity == 0.55)
        #expect(theme.sanitized.cornerRadius == 14)
        theme.surfaceOpacity = .nan
        theme.cornerRadius = .infinity
        #expect(theme.sanitized.surfaceOpacity == 0)
        #expect(theme.sanitized.cornerRadius == 18)
    }

    @Test func sanitizingTidiesTheFontFamily() {
        #expect(PaletteTheme(codeFontFamily: "  Menlo \n").sanitized.codeFontFamily == "Menlo")
        #expect(PaletteTheme(codeFontFamily: "   ").sanitized.codeFontFamily == nil)
        #expect(PaletteTheme(codeFontFamily: String(repeating: "x", count: 129)).sanitized.codeFontFamily == nil)
        #expect(PaletteTheme(codeFontFamily: String(repeating: "x", count: 128)).sanitized.codeFontFamily?.count == 128)
    }

    @Test func survivesTheJSONRoundTrip() throws {
        for preset in ThemePresets.all {
            let text = preset.theme.jsonText
            #expect(PaletteTheme(storedText: text) == preset.theme, "\(preset.id)")
            #expect(try PaletteTheme.imported(from: text).get() == preset.theme, "\(preset.id)")
        }
    }

    @Test func writesReadableKeySortedJSON() {
        let theme = PaletteTheme(appearance: .dark, colors: [.accent: ThemeColor(0xFF2E97)], surfaceOpacity: 1, cornerRadius: 14, codeFontFamily: "Menlo")
        #expect(theme.jsonText == """
        {
          "appearance" : "dark",
          "codeFont" : "Menlo",
          "colors" : {
            "accent" : "#FF2E97"
          },
          "cornerRadius" : 14,
          "surfaceOpacity" : 1,
          "toolchordTheme" : 1
        }
        """)
    }

    @Test func aBadValueCostsThatValueOnly() throws {
        let text = """
        {"toolchordTheme": 1, "appearance": "dark", "surfaceOpacity": "lots", "cornerRadius": 9,
         "colors": {"accent": "#FF2E97", "text": "crimson", "sparkles": "#FFFFFF", "well": 12},
         "codeFont": 42}
        """
        let theme = try PaletteTheme.imported(from: text).get()
        #expect(theme.appearance == .dark)
        #expect(theme.colors == [.accent: ThemeColor(0xFF2E97)])
        #expect(theme.surfaceOpacity == PaletteTheme.standard.surfaceOpacity)
        #expect(theme.cornerRadius == 9)
        #expect(theme.codeFontFamily == nil)
    }

    @Test func anUnknownAppearanceFallsBackToSystemAndDropsColors() throws {
        let text = ##"{"toolchordTheme": 1, "appearance": "sepia", "colors": {"accent": "#FF2E97"}}"##
        let theme = try PaletteTheme.imported(from: text).get()
        #expect(theme.appearance == .system)
        #expect(theme.colors.isEmpty)
    }

    @Test func aLaterVersionStillReadsWhatItCan() throws {
        let text = ##"{"toolchordTheme": 2, "appearance": "light", "sparkle": true, "colors": {"accent": "#C26A00"}}"##
        #expect(try PaletteTheme.imported(from: text).get() == PaletteTheme(appearance: .light, colors: [.accent: ThemeColor(0xC26A00)]))
    }

    @Test func storedTextNeedsNoMarkerButMustBeAnObject() {
        #expect(PaletteTheme(storedText: #"{"appearance": "light"}"#) == PaletteTheme(appearance: .light))
        #expect(PaletteTheme(storedText: "{}") == .standard)
        #expect(PaletteTheme(storedText: "[1, 2]") == nil)
        #expect(PaletteTheme(storedText: "not json") == nil)
        #expect(PaletteTheme(storedText: "") == nil)
    }

    @Test func pasteRequiresTheMarker() {
        #expect(PaletteTheme.imported(from: #"{"appearance": "dark"}"#) == .failure(.notATheme))
        #expect(PaletteTheme.imported(from: #"{"toolchordTheme": "one"}"#) == .failure(.notATheme))
        #expect(PaletteTheme.imported(from: "https://example.test") == .failure(.notATheme))
        #expect(PaletteTheme.imported(from: "") == .failure(.notATheme))
        #expect(PaletteTheme.imported(from: #"{"toolchordTheme": 1}"#) == .success(.standard))
    }

    @Test func pasteRejectsOversizedText() {
        let padding = String(repeating: " ", count: PaletteTheme.maximumImportBytes)
        #expect(PaletteTheme.imported(from: #"{"toolchordTheme": 1}"# + padding) == .failure(.tooLong))
    }

    @Test func textSizesStayInRange() {
        var sizes = ThemeTextSizes.standard
        #expect(sizes.codeFontSize == 12)
        #expect(sizes.interface == .standard)
        sizes.codeFontSize = 40
        #expect(sizes.codeFontSize == 22)
        sizes.codeFontSize = 3
        #expect(sizes.codeFontSize == 10)
        sizes.codeFontSize = 13.4
        #expect(sizes.codeFontSize == 13)
        sizes.codeFontSize = .nan
        #expect(sizes.codeFontSize == 12)
        #expect(ThemeTextSizes(codeFontSize: .infinity, interface: .large).codeFontSize == 12)
        #expect(InterfaceTextSize.allCases.map(\.scale) == [0.9, 1, 1.15, 1.3])
    }
}
