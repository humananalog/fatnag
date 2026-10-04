import XCTest
@testable import TheScale

final class ActivityHealthPromptTests: XCTestCase {
    func testOffersWhenActivityReadsLookBlockedAndWeightEngaged() {
        let probe = ActivityReadAccessProbe(
            stepsSamplesLast7d: 0,
            activeEnergySamplesLast7d: 0,
            authRequested: true,
            healthAvailable: true
        )
        XCTAssertTrue(probe.looksBlocked)
        XCTAssertTrue(
            ScaleSessionViewModel.shouldOfferActivityHealthPrompt(
                probe: probe,
                hasEngagedHealthWeight: true,
                snoozed: false,
                demoOrPromo: false
            )
        )
    }

    func testSkipsWhenSnoozedOrDemoOrNoWeightEngagement() {
        let probe = ActivityReadAccessProbe(
            stepsSamplesLast7d: 0,
            activeEnergySamplesLast7d: 0,
            authRequested: true,
            healthAvailable: true
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldOfferActivityHealthPrompt(
                probe: probe,
                hasEngagedHealthWeight: true,
                snoozed: true,
                demoOrPromo: false
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldOfferActivityHealthPrompt(
                probe: probe,
                hasEngagedHealthWeight: false,
                snoozed: false,
                demoOrPromo: false
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldOfferActivityHealthPrompt(
                probe: probe,
                hasEngagedHealthWeight: true,
                snoozed: false,
                demoOrPromo: true
            )
        )
    }

    func testSkipsWhenActivitySamplesExist() {
        let probe = ActivityReadAccessProbe(
            stepsSamplesLast7d: 12,
            activeEnergySamplesLast7d: 0,
            authRequested: true,
            healthAvailable: true
        )
        XCTAssertFalse(probe.looksBlocked)
        XCTAssertFalse(
            ScaleSessionViewModel.shouldOfferActivityHealthPrompt(
                probe: probe,
                hasEngagedHealthWeight: true,
                snoozed: false,
                demoOrPromo: false
            )
        )
    }
}
