import SwiftUI
import XCTest
@testable import TheScale

final class ScalePaletteUniverseTests: XCTestCase {
    func testDefaultUniverseIsGlacierForgeWhenSexMissing() {
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: nil), .glacierForge)
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: .male), .glacierForge)
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: .female), .bloomCopper)
    }

    func testSafeFallbackNeverUsesDeepInkOnNightVoid() {
        let night = WeeklyGoalAtmosphere.safeFallback(colorScheme: .dark)
        let ink = rgba(night.ink)
        XCTAssertGreaterThan(ink.r, 0.9, "Night fallback must use ivory ink, not deep void ink")
        XCTAssertGreaterThan(ink.g, 0.9)
        XCTAssertGreaterThan(ink.b, 0.85)

        let day = WeeklyGoalAtmosphere.safeFallback(colorScheme: .light)
        let dayInk = rgba(day.ink)
        XCTAssertLessThan(dayInk.r, 0.2, "Day fallback must use deep ink on pastel")
    }

    func testUniversesDifferAtGlanceOnTrackLight() {
        let male = WeeklyGoalAtmosphere.forBand(.onTrack, colorScheme: .light, sex: .male)
        let female = WeeklyGoalAtmosphere.forBand(.onTrack, colorScheme: .light, sex: .female)
        XCTAssertNotEqual(male.mid, female.mid)
        XCTAssertNotEqual(male.hazeA, female.hazeA)
        XCTAssertNotEqual(male.top, female.top)

        // Male mid is cool teal-green (G dominates R).
        let m = rgba(male.mid)
        XCTAssertGreaterThan(m.g, m.r)
        // Female mid is rose-tinted (R dominates B; warmer than male).
        let f = rgba(female.mid)
        XCTAssertGreaterThan(f.r, f.b)
        XCTAssertGreaterThan(f.r, m.r)
    }

    func testNightModeKeepsIvoryInkBothUniverses() {
        let bands: [WeeklyTrackBand] = [.onTrack, .ahead, .crushed, .atRisk, .unknown]
        for sex in UserBodyProfile.Sex.allCases {
            for band in bands {
                let atm = WeeklyGoalAtmosphere.forBand(band, colorScheme: .dark, sex: sex)
                let ink = rgba(atm.ink)
                XCTAssertGreaterThan(ink.r, 0.9, "\(sex) \(band) night ink")
                XCTAssertGreaterThan(ink.g, 0.9, "\(sex) \(band) night ink")
                XCTAssertGreaterThan(ink.b, 0.85, "\(sex) \(band) night ink")
            }
        }
    }

    func testDayModeKeepsDeepInkBothUniverses() {
        for sex in UserBodyProfile.Sex.allCases {
            let atm = WeeklyGoalAtmosphere.forBand(.onTrack, colorScheme: .light, sex: sex)
            let ink = rgba(atm.ink)
            XCTAssertLessThan(ink.r, 0.2)
            XCTAssertLessThan(ink.g, 0.2)
            XCTAssertLessThan(ink.b, 0.2)
        }
    }

    func testAheadAccentMatchesCrushedPerUniverse() {
        for sex in UserBodyProfile.Sex.allCases {
            let ahead = WeeklyGoalAtmosphere.forBand(.ahead, colorScheme: .light, sex: sex)
            let crushed = WeeklyGoalAtmosphere.forBand(.crushed, colorScheme: .light, sex: sex)
            XCTAssertEqual(ahead.accent, crushed.accent)
        }
    }

    func testLimeButtonLabelIsDark() {
        let maleLime = WeeklyGoalAtmosphere.forBand(.ahead, colorScheme: .dark, sex: .male).accent
        let femaleLime = WeeklyGoalAtmosphere.forBand(.crushed, colorScheme: .dark, sex: .female).accent
        for fill in [maleLime, femaleLime] {
            let ink = rgba(ScaleFillInk.label(on: fill))
            XCTAssertLessThan(ink.r, 0.2, "Lime and pale-gold fills need dark type")
            XCTAssertLessThan(ink.g, 0.2)
            XCTAssertLessThan(ink.b, 0.2)
        }

        let olive = WeeklyGoalAtmosphere.forBand(.ahead, colorScheme: .light, sex: .male).accent
        let coral = WeeklyGoalAtmosphere.forBand(.atRisk, colorScheme: .dark, sex: .male).accent
        for fill in [olive, coral] {
            let ink = rgba(ScaleFillInk.label(on: fill))
            XCTAssertGreaterThan(ink.r, 0.9, "Dark fills keep white type")
        }
    }

    func testPaywallGoldDiffersByUniverse() {
        XCTAssertNotEqual(
            ScalePaletteUniverse.glacierForge.paywallGold,
            ScalePaletteUniverse.bloomCopper.paywallGold
        )
    }

    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b, a)
    }
}
