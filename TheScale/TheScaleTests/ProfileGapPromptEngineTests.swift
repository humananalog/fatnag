import XCTest
@testable import TheScale

final class ProfileGapPromptEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProfileGapPromptStore.clear()
    }

    override func tearDown() {
        ProfileGapPromptStore.clear()
        super.tearDown()
    }

    func testPrefersLocationThenAvoidancesThenDiet() {
        var profile = UserBodyProfile.default
        profile.dietPreferenceConfirmed = false
        profile.foodAvoidancesConfirmed = false
        profile.location = ""
        profile.foodAvoidances = ""

        XCTAssertEqual(ProfileGapPromptEngine.nextGap(profile: profile), .location)

        profile.location = "Manila"
        XCTAssertEqual(ProfileGapPromptEngine.nextGap(profile: profile), .foodAvoidances)

        profile.foodAvoidancesConfirmed = true
        XCTAssertEqual(ProfileGapPromptEngine.nextGap(profile: profile), .diet)

        profile.dietPreferenceConfirmed = true
        XCTAssertNil(ProfileGapPromptEngine.nextGap(profile: profile))
    }

    func testCooldownBlocksSameDayRepeat() {
        var profile = UserBodyProfile.default
        profile.location = ""
        profile.foodAvoidancesConfirmed = true
        profile.dietPreferenceConfirmed = true
        let now = Date()
        ProfileGapPromptEngine.recordPresented(.location, now: now)
        XCTAssertNil(ProfileGapPromptEngine.nextGap(profile: profile, now: now))

        let sixDaysLater = now.addingTimeInterval(6 * 86_400)
        // Any-prompt cooldown cleared, but same-gap still blocks location for 18d.
        XCTAssertNil(ProfileGapPromptEngine.nextGap(profile: profile, now: sixDaysLater))

        let nineteenDaysLater = now.addingTimeInterval(19 * 86_400)
        XCTAssertEqual(
            ProfileGapPromptEngine.nextGap(profile: profile, now: nineteenDaysLater),
            .location
        )
    }

    func testBlankAvoidancesStayMissingUntilConfirmed() {
        var profile = UserBodyProfile.default
        profile.location = "HK"
        profile.foodAvoidances = ""
        profile.foodAvoidancesConfirmed = false
        XCTAssertTrue(ProfileGapPromptEngine.isMissing(.foodAvoidances, profile: profile))

        profile.foodAvoidancesConfirmed = true
        XCTAssertFalse(ProfileGapPromptEngine.isMissing(.foodAvoidances, profile: profile))
    }
}

@MainActor
final class LifestyleOnboardingTests: XCTestCase {
    func testLifestyleFieldsOptionalAndBuildProfile() {
        let flow = OnboardingFlowModel()
        flow.step = .lifestyle
        XCTAssertTrue(flow.canAdvance)

        flow.diet = .pescatarian
        flow.markDietConfirmed()
        flow.location = "Central HK"
        flow.useLocalContext = true
        flow.foodAvoidances = "shellfish"
        let profile = flow.buildProfile()
        XCTAssertEqual(profile.dietPreference, .pescatarian)
        XCTAssertTrue(profile.dietPreferenceConfirmed)
        XCTAssertEqual(profile.location, "Central HK")
        XCTAssertTrue(profile.useLocalContext)
        XCTAssertEqual(profile.foodAvoidances, "shellfish")
        XCTAssertTrue(profile.foodAvoidancesConfirmed)
    }

    func testBlankLifestyleLeavesGapsForLater() {
        let flow = OnboardingFlowModel()
        flow.name = "Alex"
        flow.sex = .male
        flow.ageYears = 30
        flow.heightCm = 175
        flow.currentWeightKg = 80
        flow.idealKg = 72
        flow.goalDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        let profile = flow.buildProfile()
        XCTAssertFalse(profile.dietPreferenceConfirmed)
        XCTAssertTrue(profile.location.isEmpty)
        XCTAssertFalse(profile.foodAvoidancesConfirmed)
        XCTAssertEqual(ProfileGapPromptEngine.nextGap(profile: profile), .location)
    }
}
