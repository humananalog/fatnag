import XCTest
@testable import TheScale

final class FoundationModelCoachTests: XCTestCase {
    func testAvailabilityStatusSummaryIsNonEmpty() {
        FoundationModelAvailability.resetRuntimeFailureForTests()
        let summary = FoundationModelAvailability.statusSummary
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(
            summary.contains("Apple Intelligence"),
            "Expected Apple Intelligence status line, got: \(summary)"
        )
    }

    func testShortLabelIsStable() {
        FoundationModelAvailability.resetRuntimeFailureForTests()
        let label = FoundationModelAvailability.shortLabel
        XCTAssertTrue(label == "FM ready" || label == "FM off")
    }

    func testSimulatorSkipsFoundationModels() {
        FoundationModelAvailability.resetRuntimeFailureForTests()
        #if targetEnvironment(simulator)
        XCTAssertFalse(FoundationModelAvailability.isAvailable)
        XCTAssertEqual(FoundationModelAvailability.shortLabel, "FM off")
        XCTAssertTrue(FoundationModelAvailability.statusSummary.lowercased().contains("simulator"))
        #endif
    }

    func testRuntimeFailureTripsAvailability() {
        FoundationModelAvailability.resetRuntimeFailureForTests()
        #if !targetEnvironment(simulator)
        // On device we may start available; trip the breaker and ensure we stay off.
        let before = FoundationModelAvailability.isAvailable
        #endif
        FoundationModelAvailability.noteRuntimeFailure(
            NSError(
                domain: "ModelManagerServices.ModelManagerError",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "InferenceError::hostFailed::promptTemplateNotFound"
                ]
            )
        )
        XCTAssertFalse(FoundationModelAvailability.isAvailable)
        XCTAssertTrue(
            FoundationModelAvailability.statusSummary.lowercased().contains("prompt template")
                || FoundationModelAvailability.statusSummary.lowercased().contains("host failed")
        )
        FoundationModelAvailability.resetRuntimeFailureForTests()
        #if !targetEnvironment(simulator)
        _ = before
        #endif
    }

    func testRefineNotificationFallsBackWhenUnavailableOrFails() async {
        let result = await FoundationModelCoach.refineNotificationCopy(
            profileName: "Alex",
            kind: "bad-trend",
            fallbackTitle: "Alex: scale check",
            fallbackBody: "Up 0.5 kg this week. Worth a look.",
            context: "unit-test"
        )
        // On CI / Mac without Apple Intelligence, FM is off → exact fallback.
        // On a device with FM, copy may change but must stay non-empty and sanitized.
        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.body.isEmpty)
        XCTAssertFalse(result.title.contains("\u{2014}"))
        XCTAssertFalse(result.body.contains("\u{2014}"))
        if !FoundationModelAvailability.isAvailable {
            XCTAssertEqual(result.title, "Alex: scale check")
            XCTAssertEqual(result.body, "Up 0.5 kg this week. Worth a look.")
            XCTAssertFalse(result.usedFoundationModel)
        }
    }

    func testShouldSendPingDefaultsAllowWhenFMOff() async {
        let result = await FoundationModelCoach.shouldSendPing(
            profileName: "Alex",
            kind: "watchLikelyNotWorn",
            algorithmicReason: "Moved today but HR samples are sparse."
        )
        if !FoundationModelAvailability.isAvailable {
            XCTAssertTrue(result.shouldNotify)
            XCTAssertFalse(result.usedFoundationModel)
        } else {
            // Judgment may suppress; still must return a reason.
            XCTAssertFalse(result.reason.isEmpty)
        }
    }

    func testSummarizeDigestNilWhenEmptyOrUnavailable() async {
        let empty = await FoundationModelCoach.summarizeFitnessDigest(
            profileName: "Alex",
            digestBlock: "   "
        )
        XCTAssertNil(empty)
        if !FoundationModelAvailability.isAvailable {
            let blocked = await FoundationModelCoach.summarizeFitnessDigest(
                profileName: "Alex",
                digestBlock: "Steps today: 8000"
            )
            XCTAssertNil(blocked)
        }
    }

    func testMemoryExtractEmptyForShortText() async {
        let facts = await FoundationModelCoach.extractMemoryFacts(from: "hi")
        XCTAssertTrue(facts.isEmpty)
    }
}
