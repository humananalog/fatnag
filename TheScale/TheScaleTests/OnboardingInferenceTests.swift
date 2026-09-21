import XCTest
@testable import TheScale

final class OnboardingInferenceTests: XCTestCase {
    func testLocalInfersDietLocationLanguage() {
        let draft = OnboardingLocalInference.infer(
            from: "Filipina in Manila, vegetarian, prefer Tagalog, aiming for 62 kg",
            name: "Alex"
        )
        XCTAssertEqual(draft.diet, .vegetarian)
        XCTAssertEqual(draft.location, "Manila")
        XCTAssertEqual(draft.preferredLanguage, "Tagalog")
        XCTAssertEqual(draft.idealWeightKg, 62)
        XCTAssertFalse(draft.usedNetwork)
        XCTAssertNotNil(draft.culturalVibe)
    }

    func testLocalInfersPescatarianAndBodyFat() {
        let draft = OnboardingLocalInference.infer(
            from: "pescatarian in Hong Kong, body fat to 18%",
            name: "Sam"
        )
        XCTAssertEqual(draft.diet, .pescatarian)
        XCTAssertEqual(draft.location, "Hong Kong")
        XCTAssertEqual(draft.idealBodyFatPercent, 18)
    }

    func testParseGrokJSON() {
        let raw = """
        Here you go:
        {"diet":"vegan","location":"Singapore","ethnicity":"Chinese","preferredLanguage":"English","culturalVibe":"SG office athlete","idealWeightKg":65.5,"idealBodyFatPercent":null}
        """
        let draft = GrokClient.parseOnboardingInferenceJSON(raw, usedNetwork: true)
        XCTAssertEqual(draft.diet, .vegan)
        XCTAssertEqual(draft.location, "Singapore")
        XCTAssertEqual(draft.ethnicity, "Chinese")
        XCTAssertEqual(draft.idealWeightKg, 65.5)
        XCTAssertNil(draft.idealBodyFatPercent)
        XCTAssertTrue(draft.usedNetwork)
    }

    func testMergePrefersRemoteWhenPresent() {
        let local = OnboardingInferenceDraft(
            diet: .omnivore,
            location: "Manila",
            ethnicity: nil,
            preferredLanguage: "English",
            culturalVibe: "local",
            idealWeightKg: nil,
            idealBodyFatPercent: nil,
            usedNetwork: false,
            sourceLabel: "on-device"
        )
        let remote = OnboardingInferenceDraft(
            diet: .vegan,
            location: nil,
            ethnicity: "Filipina",
            preferredLanguage: "Tagalog",
            culturalVibe: nil,
            idealWeightKg: 60,
            idealBodyFatPercent: 20,
            usedNetwork: true,
            sourceLabel: "grok"
        )
        let merged = GrokClient.mergeInference(local: local, remote: remote)
        XCTAssertEqual(merged.diet, .vegan)
        XCTAssertEqual(merged.location, "Manila")
        XCTAssertEqual(merged.ethnicity, "Filipina")
        XCTAssertEqual(merged.preferredLanguage, "Tagalog")
        XCTAssertEqual(merged.culturalVibe, "local")
        XCTAssertEqual(merged.idealWeightKg, 60)
        XCTAssertTrue(merged.usedNetwork)
    }

    @MainActor
    func testReviewPromptGatesOnWeighInCount() {
        ScaleAppReviewPrompt.debugReset()
        XCTAssertFalse(ScaleAppReviewPrompt.shouldOfferSoftPrompt())
        ScaleAppReviewPrompt.successfulWeighIns = 2
        XCTAssertFalse(ScaleAppReviewPrompt.shouldOfferSoftPrompt())
        ScaleAppReviewPrompt.successfulWeighIns = 3
        XCTAssertTrue(ScaleAppReviewPrompt.shouldOfferSoftPrompt())
        ScaleAppReviewPrompt.markSoftPromptShown()
        XCTAssertFalse(ScaleAppReviewPrompt.shouldOfferSoftPrompt())
        ScaleAppReviewPrompt.debugReset()
    }
}
