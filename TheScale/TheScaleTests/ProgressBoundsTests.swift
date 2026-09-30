import XCTest
@testable import TheScale

final class ProgressBoundsTests: XCTestCase {
    func testClampKeepsValueInsideTotal() {
        let mid = ProgressBounds.clamp(42, total: 100)
        XCTAssertEqual(mid.value, 42)
        XCTAssertEqual(mid.total, 100)

        let over = ProgressBounds.clamp(120, total: 100)
        XCTAssertEqual(over.value, 100)
        XCTAssertEqual(over.total, 100)

        let under = ProgressBounds.clamp(-5, total: 100)
        XCTAssertEqual(under.value, 0)
        XCTAssertEqual(under.total, 100)
    }

    func testClampRejectsNonFiniteAndNonPositiveTotal() {
        let nan = ProgressBounds.clamp(.nan, total: 100)
        XCTAssertEqual(nan.value, 0)
        XCTAssertEqual(nan.total, 100)

        let inf = ProgressBounds.clamp(.infinity, total: 50)
        XCTAssertEqual(inf.value, 0)
        XCTAssertEqual(inf.total, 50)

        let badTotal = ProgressBounds.clamp(0.5, total: 0)
        XCTAssertEqual(badTotal.value, 0.5)
        XCTAssertEqual(badTotal.total, 1)

        let negTotal = ProgressBounds.clamp(2, total: -10)
        XCTAssertEqual(negTotal.value, 1)
        XCTAssertEqual(negTotal.total, 1)
    }

    func testAheadGaugeCapMatchesProgressSheetVisualMax() {
        // Progress ACTION gauge allows visual "ahead" up to 1.2 — never beyond.
        XCTAssertEqual(ProgressBounds.clampedValue(1.35, total: 1.2), 1.2)
        XCTAssertEqual(ProgressBounds.clampedValue(0.85, total: 1.2), 0.85)
    }

    func testScaleBoundedProgressClampsQuotaOvershoot() {
        // Settings / Paywall quota bars must never feed SwiftUI ProgressView.
        let bounds = ProgressBounds.clamp(140, total: 100)
        XCTAssertEqual(bounds.value, 100)
        XCTAssertEqual(bounds.total, 100)
        XCTAssertEqual(ProgressBounds.clampedValue(Double(140), total: 100), 100)
    }

    func testSafeLengthRejectsNonFiniteAndNegative() {
        XCTAssertEqual(ProgressBounds.safeLength(.nan), 0)
        XCTAssertEqual(ProgressBounds.safeLength(.infinity), 0)
        XCTAssertEqual(ProgressBounds.safeLength(-12), 0)
        XCTAssertEqual(ProgressBounds.safeLength(0), 0)
        XCTAssertEqual(ProgressBounds.safeLength(42.5), 42.5)
    }

    func testDebugLogThrottleSuppressesBursts() {
        #if DEBUG
        ScaleDebugLog.resetThrottleStateForTests()
        // First call prints; immediate second with same key is suppressed (no crash / no throw).
        ScaleDebugLog.throttled("unit.test.throttle", every: 60, "first")
        ScaleDebugLog.throttled("unit.test.throttle", every: 60, "second")
        ScaleDebugLog.resetThrottleStateForTests()
        #endif
    }
}

final class HomeMenuPageSwipeTests: XCTestCase {
    func testSettingsDisablesMenuPageSwipe() {
        XCTAssertFalse(HomeGlassDestination.settings.allowsMenuPageSwipe)
        for page in HomeGlassDestination.allCases where page != .settings {
            XCTAssertTrue(page.allowsMenuPageSwipe)
        }
    }
}
