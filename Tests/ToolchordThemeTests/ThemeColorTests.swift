import Foundation
import Testing
@testable import ToolchordTheme

@Suite struct ThemeColorTests {
    @Test func parsesTheHexSpellingsPeoplePaste() {
        #expect(ThemeColor(hex: "#FF2E97") == ThemeColor(0xFF2E97))
        #expect(ThemeColor(hex: "ff2e97") == ThemeColor(0xFF2E97))
        #expect(ThemeColor(hex: "  #ff2E97\n") == ThemeColor(0xFF2E97))
        #expect(ThemeColor(hex: "#F80") == ThemeColor(0xFF8800))
    }

    @Test func rejectsWhatIsNotAnOpaqueColor() {
        for text in ["", "#", "#FF2E9", "#FF2E977", "#FF2E9780", "+FF2E97", "#GG2E97", "0xFF2E97", "red", "#FF 2E97", "#１２３"] {
            #expect(ThemeColor(hex: text) == nil, "\(text)")
        }
    }

    @Test func formatsAsUppercaseHexThatParsesAgain() {
        let color = ThemeColor(0x0A84FF)
        #expect(color.hex == "#0A84FF")
        #expect(ThemeColor(hex: color.hex) == color)
    }

    @Test func clampsComponentsAndTurnsNaNIntoZero() {
        let color = ThemeColor(red: 2, green: -1, blue: .nan)
        #expect(color == ThemeColor(red: 1, green: 0, blue: 0))
        #expect(color.hex == "#FF0000")
        #expect(ThemeColor(red: .infinity, green: -.infinity, blue: 0.5).hex == "#FF0080")
    }

    @Test func roundingMatchesWhatHexStores() {
        let computed = ThemeColor(red: 0.5, green: 0.25, blue: 1)
        #expect(computed.rounded == ThemeColor(hex: computed.hex))
        #expect(computed.rounded.rounded == computed.rounded)
    }

    @Test func luminanceAndContrastFollowWCAG() {
        #expect(ThemeColor.white.relativeLuminance == 1)
        #expect(ThemeColor.black.relativeLuminance == 0)
        #expect(abs(ThemeColor.black.contrast(with: .white) - 21) < 1e-9)
        #expect(ThemeColor.white.contrast(with: .black) == ThemeColor.black.contrast(with: .white))
        #expect(ThemeColor(0x777777).contrast(with: .white) > 4.47)
        #expect(ThemeColor(0x777777).contrast(with: .white) < 4.49)
        // Green carries most of the luminance.
        #expect(ThemeColor(0x00FF00).relativeLuminance > ThemeColor(0x0000FF).relativeLuminance)
    }

    @Test func blendsInSRGB() {
        let gray = ThemeColor.white.blended(over: .black, opacity: 0.5)
        #expect(gray == ThemeColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(ThemeColor(0x123456).blended(over: .white, opacity: 1) == ThemeColor(0x123456))
        #expect(ThemeColor(0x123456).blended(over: .white, opacity: 0) == .white)
        #expect(ThemeColor(0x123456).blended(over: .white, opacity: .nan) == .white)
    }

    @Test func readableForegroundAlwaysReadsWell() {
        for value: UInt32 in [0x000000, 0xFFFFFF, 0x777777, 0x808080, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFD500, 0x0A84FF] {
            let color = ThemeColor(value)
            #expect(color.readableForeground.contrast(with: color) >= 4.58, "\(color)")
        }
        #expect(ThemeColor(0xFFD500).readableForeground == .black)
        #expect(ThemeColor(0x1A1033).readableForeground == .white)
    }

    @Test func raisingContrastReachesTheMinimumWithTheSmallestStep() {
        let backgrounds = [ThemeColor(0xFFFFFF), ThemeColor(0xF2F2F5)]
        let pale = ThemeColor(0x8FB3E0)
        let raised = pale.raisingContrast(to: 4.5, against: backgrounds)
        #expect(raised.worstContrast(against: backgrounds) >= 4.5)
        // Barely past the minimum: a bigger step would be visibly darker than needed.
        #expect(raised.worstContrast(against: backgrounds) < 4.52)
        // Darker on a light background, and still bluish.
        #expect(raised.relativeLuminance < pale.relativeLuminance)
        #expect(raised.blue > raised.red)
    }

    @Test func raisingContrastLightensOnDarkBackgrounds() {
        let backgrounds = [ThemeColor(0x1A1033)]
        let dim = ThemeColor(0x6A3D8F)
        let raised = dim.raisingContrast(to: 7, against: backgrounds)
        #expect(raised.worstContrast(against: backgrounds) >= 7)
        #expect(raised.relativeLuminance > dim.relativeLuminance)
    }

    @Test func raisingContrastFindsAMidToneBetweenClashingBackgrounds() {
        // Neither end passes on both black and white, but a mid-gray does.
        let backgrounds = [ThemeColor.black, ThemeColor.white]
        #expect(ThemeColor.black.worstContrast(against: backgrounds) < 4.5)
        #expect(ThemeColor.white.worstContrast(against: backgrounds) < 4.5)
        let raised = ThemeColor.white.raisingContrast(to: 4.5, against: backgrounds)
        #expect(raised.worstContrast(against: backgrounds) >= 4.5)
        #expect(raised != .black && raised != .white)
    }

    @Test func raisingContrastFindsANarrowPassingRange() {
        // Against black and near-white, only a sliver of grays reaches
        // 4.5:1 on both: narrower than any fixed sampling step.
        let backgrounds = [ThemeColor.black, ThemeColor(0xFBFBFB)]
        let passing = ThemeColor.passingLuminances(minimum: 4.5, against: backgrounds)
        #expect(passing.count == 1)
        #expect((passing.first.map { $0.upperBound - $0.lowerBound } ?? 1) < 0.005)
        let raised = ThemeColor.white.raisingContrast(to: 4.5, against: backgrounds)
        #expect(raised.worstContrast(against: backgrounds) >= 4.5 - 1e-9)
    }

    @Test func raisingContrastTakesTheNearerDirection() {
        // Both black and white pass eventually; white gets there sooner.
        let background = ThemeColor(0x5E5E5E)
        let start = ThemeColor(0x242424)
        let raised = start.raisingContrast(to: 3, against: [background])
        #expect(raised.contrast(with: background) >= 3 - 1e-9)
        #expect(raised.relativeLuminance > start.relativeLuminance)
        #expect(raised.contrast(with: background) < 3.01)
    }

    @Test func raisingContrastLeavesPassingColorsAlone() {
        let color = ThemeColor(0x111111)
        #expect(color.raisingContrast(to: 4.5, against: [.white]) == color)
        #expect(color.raisingContrast(to: 4.5, against: []) == color)
    }

    @Test func raisingContrastFallsBackToTheBestEndWhenTheMinimumIsOutOfReach() {
        // Neither black nor white reaches 7:1 on mid-gray.
        let gray = ThemeColor(0x767676)
        let raised = ThemeColor(0x808080).raisingContrast(to: 7, against: [gray])
        #expect(raised == .black || raised == .white)
    }

    @Test func codesAsAHexString() throws {
        let data = try JSONEncoder().encode([ThemeColor(0xFF2E97)])
        #expect(String(decoding: data, as: UTF8.self) == ##"["#FF2E97"]"##)
        #expect(try JSONDecoder().decode([ThemeColor].self, from: Data(##"["#ff2e97"]"##.utf8)) == [ThemeColor(0xFF2E97)])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([ThemeColor].self, from: Data(#"["crimson"]"#.utf8))
        }
    }
}
