import XCTest
@testable import TheScale

final class HealthSyncedScaleDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_775_000_000) // fixed
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testIgnoresAppleHealthAndOurApp() {
        let samples = [
            HealthWeightSample(
                weightKg: 80,
                date: now.addingTimeInterval(-86_400),
                sourceName: "Health",
                sourceBundleId: "com.apple.Health"
            ),
            HealthWeightSample(
                weightKg: 79.8,
                date: now.addingTimeInterval(-172_800),
                sourceName: "FATNAG",
                sourceBundleId: "app.thescale.ios"
            ),
        ]
        let signal = HealthSyncedScaleDetector.evaluate(samples: samples, now: now, calendar: calendar)
        XCTAssertFalse(signal.isLikely)
    }

    func testDetectsKnownVendorWithOneFreshSample() {
        let samples = [
            HealthWeightSample(
                weightKg: 82.1,
                date: now.addingTimeInterval(-86_400),
                sourceName: "Withings",
                sourceBundleId: "com.withings.wiScaleNG"
            )
        ]
        let signal = HealthSyncedScaleDetector.evaluate(samples: samples, now: now, calendar: calendar)
        XCTAssertTrue(signal.isLikely)
        XCTAssertEqual(signal.primarySourceName, "Withings")
        XCTAssertEqual(signal.primaryBundleId, "com.withings.wiScaleNG")
    }

    func testDetectsRecurringForeignSource() {
        let samples = [
            HealthWeightSample(
                weightKg: 90,
                date: now.addingTimeInterval(-86_400),
                sourceName: "MyScaleApp",
                sourceBundleId: "com.example.myscale"
            ),
            HealthWeightSample(
                weightKg: 90.2,
                date: now.addingTimeInterval(-3 * 86_400),
                sourceName: "MyScaleApp",
                sourceBundleId: "com.example.myscale"
            ),
        ]
        let signal = HealthSyncedScaleDetector.evaluate(samples: samples, now: now, calendar: calendar)
        XCTAssertTrue(signal.isLikely)
        XCTAssertEqual(signal.primarySourceName, "MyScaleApp")
    }

    func testSingleUnknownForeignSourceIsNotEnough() {
        let samples = [
            HealthWeightSample(
                weightKg: 70,
                date: now.addingTimeInterval(-86_400),
                sourceName: "RandomTracker",
                sourceBundleId: "com.example.random"
            )
        ]
        let signal = HealthSyncedScaleDetector.evaluate(samples: samples, now: now, calendar: calendar)
        XCTAssertFalse(signal.isLikely)
    }

    func testStaleKnownVendorAloneIsIgnored() {
        let samples = [
            HealthWeightSample(
                weightKg: 80,
                date: now.addingTimeInterval(-40 * 86_400),
                sourceName: "Renpho",
                sourceBundleId: "com.renpho.health"
            )
        ]
        let signal = HealthSyncedScaleDetector.evaluate(samples: samples, now: now, calendar: calendar)
        XCTAssertFalse(signal.isLikely)
    }
}
