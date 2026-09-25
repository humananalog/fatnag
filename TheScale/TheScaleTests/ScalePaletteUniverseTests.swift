import SwiftUI
import XCTest
@testable import TheScale

final class ScalePaletteUniverseTests: XCTestCase {
    func testDefaultUniverseIsGlacierForgeWhenSexMissing() {
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: nil), .glacierForge)
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: .male), .glacierForge)
        XCTAssertEqual(ScalePaletteUniverse.resolve(sex: .female), .bloomCopper)
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
        for sex in UserBodyProfile.Sex.allCases {
            let atm = WeeklyGoalAtmosphere.forBand(.onTrack, colorScheme: .dark, sex: sex)
            let ink = rgba(atm.ink)
            XCTAssertGreaterThan(ink.r, 0.9)
            XCTAssertGreaterThan(ink.g, 0.9)
            XCTAssertGreaterThan(ink.b, 0.85)
        }
    }

    func testAheadAccentMatchesCrushedPerUniverse() {
        for sex in UserBodyProfile.Sex.allCases {
            let ahead = WeeklyGoalAtmosphere.forBand(.ahead, colorScheme: .light, sex: sex)
            let crushed = WeeklyGoalAtmosphere.forBand(.crushed, colorScheme: .light, sex: sex)
            XCTAssertEqual(ahead.accent, crushed.accent)
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
