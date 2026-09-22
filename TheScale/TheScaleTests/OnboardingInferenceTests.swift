import XCTest
@testable import TheScale

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testThreeStepSequenceWithInjectedInference() async {
        let flow = OnboardingFlowModel()
        XCTAssertEqual(flow.step, .identity)
        XCTAssertFalse(flow.canAdvance)

        flow.name = "Alex"
        flow.freeform = "Filipina in Manila, vegetarian, Tagalog, aiming 62 kg"
        XCTAssertTrue(flow.canAdvance)

        await flow.advance(infer: { _ in
            XCTFail("Inference should not run on identity → body")
            return .empty
        })
        XCTAssertEqual(flow.step, .body)

        flow.heightCm = 162
        flow.ageYears = 28
        flow.sex = .female
        flow.idealKg = 65
        XCTAssertTrue(flow.canAdvance)

        await flow.advance(infer: { _ in
            XCTFail("Inference should not run on body → anatomy")
            return .empty
        })
        XCTAssertEqual(flow.step, .anatomy)

        flow.currentWeightKg = 70
        XCTAssertTrue(flow.canAdvance)

        await flow.advance { model in
            XCTAssertEqual(model.name, "Alex")
            return OnboardingInferenceDraft(
                diet: .vegetarian,
                location: "Manila",
                ethnicity: "Filipina",
                preferredLanguage: "Tagalog",
                culturalVibe: "Filipina in Manila, vegetarian",
                idealWeightKg: 62,
                idealBodyFatPercent: nil,
                intermittentFasting: nil,
                usedNetwork: false,
                sourceLabel: "foundation-model"
            )
        }

        XCTAssertEqual(flow.step, .dream)
        XCTAssertEqual(flow.diet, .vegetarian)
        XCTAssertEqual(flow.location, "Manila")
        XCTAssertEqual(flow.preferredLanguage, "Tagalog")
        XCTAssertEqual(flow.idealKg, 62)
        XCTAssertEqual(flow.inferenceNote, "On-device Coach filled these from your note. Edit freely.")

        // Stretch the date so pace is accepted.
        flow.goalDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        flow.currentWeightKg = 70
        flow.refreshPaceAndDifficulty()
        XCTAssertTrue(flow.canAdvance)
        await flow.advance(infer: nil)
        XCTAssertEqual(flow.step, .lifestyle)

        XCTAssertTrue(flow.canAdvance)
        await flow.advance(infer: nil)
        XCTAssertEqual(flow.step, .confirm)

        XCTAssertFalse(flow.canAdvance)
        flow.acceptedLegal = true
        XCTAssertTrue(flow.canAdvance)

        let profile = flow.buildProfile()
        XCTAssertEqual(profile.displayName, "Alex")
        XCTAssertEqual(profile.sex, .female)
        XCTAssertEqual(profile.ageYears, 28)
        XCTAssertEqual(profile.dietPreference, .vegetarian)
        XCTAssertTrue(profile.dietPreferenceConfirmed)
        XCTAssertEqual(profile.location, "Manila")
        XCTAssertEqual(profile.idealWeightKg, 62)
        XCTAssertEqual(profile.startingWeightKg, 70)
    }

    func testBodyStepRequiresAdultAgeAndGender() {
        let flow = OnboardingFlowModel()
        flow.step = .body
        flow.heightCm = 170
        flow.idealKg = 65

        XCTAssertFalse(flow.canAdvance)
        XCTAssertFalse(flow.hasChosenGender)

        flow.sex = .male
        flow.ageYears = 17
        XCTAssertFalse(flow.canAdvance)
        XCTAssertEqual(flow.ageValidationMessage, "You must be 18 or older.")

        flow.ageYears = 18
        XCTAssertTrue(flow.isAdultAge)
        XCTAssertTrue(flow.canAdvance)
        XCTAssertNil(flow.ageValidationMessage)

        flow.sex = nil
        XCTAssertFalse(flow.canAdvance)

        flow.sex = .female
        let profile = flow.buildProfile()
        XCTAssertEqual(profile.sex, .female)
        XCTAssertGreaterThanOrEqual(profile.ageYears, UserBodyProfile.minimumAgeYears)
    }

    func testBackNavigation() async {
        let flow = OnboardingFlowModel()
        flow.name = "Sam"
        await flow.advance(infer: { _ in .empty })
        XCTAssertEqual(flow.step, .body)
        flow.goBack()
        XCTAssertEqual(flow.step, .identity)
    }

    func testHeuristicsUsedWhenFMDisabled() async {
        let flow = OnboardingFlowModel()
        flow.name = "Alex"
        flow.freeform = "pescatarian in Hong Kong, body fat to 18%"
        flow.allowOnDevicePrefill = false
        flow.heightCm = 170
        flow.ageYears = 30
        flow.sex = .male

        await flow.advance(infer: nil) // identity → body
        await flow.advance(infer: nil) // body → anatomy
        // Manually run default inference path with FM disallowed via allowOnDevicePrefill
        await flow.runInference()
        XCTAssertEqual(flow.diet, .pescatarian)
        XCTAssertEqual(flow.location, "Hong Kong")
        XCTAssertEqual(flow.idealBodyFat, 18)
        XCTAssertNotEqual(flow.inferenceNote, "On-device Coach filled these from your note. Edit freely.")
    }
}

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

    func testLocalInfersStructuredIF168() {
        let draft = OnboardingLocalInference.infer(
            from: "Filipina in Manila, IF 16-8, aiming 62 kg",
            name: "Alex"
        )
        guard let fasting = draft.intermittentFasting else {
            XCTFail("expected structured IF window")
            return
        }
        XCTAssertEqual(fasting.protocolLabel, "16-8")
        XCTAssertEqual(fasting.eatingWindowStartMinutes, 12 * 60)
        XCTAssertEqual(fasting.eatingWindowEndMinutes, 20 * 60)
        XCTAssertEqual(fasting.fastingHours, 16)
        // IF alone is not a special diet.
        XCTAssertEqual(draft.diet, .omnivore)
        XCTAssertEqual(draft.idealWeightKg, 62)
    }

    func testFMDraftMapping() {
        let fm = OnboardingProfileFMDraft(
            diet: "vegan",
            location: "Singapore",
            ethnicity: "Chinese",
            preferredLanguage: "English",
            culturalVibe: "SG office athlete",
            idealWeightKg: 65.5,
            idealBodyFatPercent: 0
        )
        let draft = FoundationModelCoach.draft(from: fm)
        XCTAssertEqual(draft.diet, .vegan)
        XCTAssertEqual(draft.location, "Singapore")
        XCTAssertEqual(draft.ethnicity, "Chinese")
        XCTAssertEqual(draft.idealWeightKg, 65.5)
        XCTAssertNil(draft.idealBodyFatPercent)
        XCTAssertEqual(draft.sourceLabel, "foundation-model")
        XCTAssertFalse(draft.usedNetwork)
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
            intermittentFasting: nil,
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
            intermittentFasting: nil,
            usedNetwork: false,
            sourceLabel: "foundation-model"
        )
        let merged = OnboardingLocalInference.merge(local: local, remote: remote)
        XCTAssertEqual(merged.diet, .vegan)
        XCTAssertEqual(merged.location, "Manila")
        XCTAssertEqual(merged.ethnicity, "Filipina")
        XCTAssertEqual(merged.preferredLanguage, "Tagalog")
        XCTAssertEqual(merged.culturalVibe, "local")
        XCTAssertEqual(merged.idealWeightKg, 60)
        XCTAssertEqual(merged.sourceLabel, "foundation-model")
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
