import XCTest
@testable import TheScale

final class TargetFeasibilityTests: XCTestCase {
    private func maleProfile(heightCm: Double = 178, age: Double = 35) -> UserBodyProfile {
        UserBodyProfile(
            displayName: "Alex",
            heightCm: heightCm,
            ageYears: age,
            sex: .male,
            idealWeightKg: UserBodyProfile.suggestedIdealWeightKg(heightCm: heightCm)
        )
    }

    private func femaleProfile(heightCm: Double = 162, age: Double = 28) -> UserBodyProfile {
        UserBodyProfile(
            displayName: "Sam",
            heightCm: heightCm,
            ageYears: age,
            sex: .female,
            idealWeightKg: UserBodyProfile.suggestedIdealWeightKg(heightCm: heightCm)
        )
    }

    func testExtractWeightTargetFromNaturalLanguage() {
        let targets = CoachTargetExtractor.extract(from: "I want to get to 80 kg by summer")
        XCTAssertEqual(targets, [.weightKg(80)])
    }

    func testExtractBodyFatTarget() {
        let targets = CoachTargetExtractor.extract(from: "My goal body fat is 18%")
        XCTAssertTrue(targets.contains(.bodyFatPercent(18)))
    }

    func testAcceptSensibleMaleWeightTarget() {
        let profile = maleProfile()
        let result = TargetFeasibility.evaluate(
            stated: .weightKg(80),
            profile: profile,
            currentKg: 92,
            currentBodyFatPercent: 24
        )
        XCTAssertEqual(result.verdict, .accepted)
        XCTAssertEqual(result.appliedWeightKg, 80)
        XCTAssertNotNil(result.statedBMI)
        XCTAssertGreaterThan(result.statedBMI!, 18.5)
        XCTAssertLessThan(result.statedBMI!, 30)
    }

    func testRejectDangerouslyThinFemaleTarget() {
        let profile = femaleProfile(heightCm: 165)
        // ~40 kg at 165 cm is BMI ~14.7
        let result = TargetFeasibility.evaluate(
            stated: .weightKg(40),
            profile: profile,
            currentKg: 68,
            currentBodyFatPercent: 28
        )
        XCTAssertEqual(result.verdict, .rejected)
        XCTAssertNil(result.appliedWeightKg)
        XCTAssertNotNil(result.suggestedWeightKg)
        XCTAssertTrue(result.coachNote.lowercased().contains("dangerous") || result.coachNote.lowercased().contains("thin"))
    }

    func testRejectEssentialFloorBodyFatFromHighCurrent() {
        let profile = maleProfile()
        let result = TargetFeasibility.evaluate(
            stated: .bodyFatPercent(5),
            profile: profile,
            currentKg: 110,
            currentBodyFatPercent: 40
        )
        // 5% is at essential floor for male; from 40% with ≥15pt drop → rejected
        XCTAssertEqual(result.verdict, .rejected)
        XCTAssertNil(result.appliedBodyFatPercent)
        XCTAssertNotNil(result.suggestedBodyFatPercent)
        XCTAssertTrue(result.coachNote.lowercased().contains("not storing") || result.coachNote.lowercased().contains("waypoint"))
    }

    func testRejectBelowEssentialFemaleBodyFat() {
        let profile = femaleProfile()
        let result = TargetFeasibility.evaluate(
            stated: .bodyFatPercent(8),
            profile: profile,
            currentKg: 70,
            currentBodyFatPercent: 30
        )
        XCTAssertEqual(result.verdict, .rejected)
        XCTAssertNil(result.appliedBodyFatPercent)
    }

    func testAcceptRealisticFemaleBodyFat() {
        let profile = femaleProfile()
        let result = TargetFeasibility.evaluate(
            stated: .bodyFatPercent(24),
            profile: profile,
            currentKg: 72,
            currentBodyFatPercent: 30
        )
        XCTAssertEqual(result.verdict, .accepted)
        XCTAssertEqual(result.appliedBodyFatPercent, 24)
    }

    func testObeseMaleWaypointCaution() {
        let profile = maleProfile(heightCm: 175)
        // 110 kg at 175 cm is obese BMI
        let result = TargetFeasibility.evaluate(
            stated: .weightKg(110),
            profile: profile,
            currentKg: 110,
            currentBodyFatPercent: 35
        )
        XCTAssertTrue(
            result.verdict == .acceptedWithCaution || result.verdict == .accepted
        )
    }

    func testScientificProjectionReachesTargetAtSafePace() throws {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: day * 40)
        var samples: [HealthMetricSample] = []
        for i in 0..<8 {
            samples.append(
                HealthMetricSample(
                    value: 95 - Double(i) * 0.15,
                    date: now.addingTimeInterval(-day * Double(28 - i * 3))
                )
            )
        }
        let projection = try XCTUnwrap(
            HealthChartMath.scientificProjectWeight(
                samples: samples,
                idealKg: 80,
                currentKg: 94,
                heightCm: 178,
                sex: .male,
                digest: nil,
                now: now
            )
        )
        XCTAssertFalse(projection.temperedPath.isEmpty)
        XCTAssertLessThan(projection.temperedSlopeKgPerDay, 0)
        let maxLossPerDay = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 94) / 7.0
        XCTAssertGreaterThanOrEqual(projection.temperedSlopeKgPerDay, -maxLossPerDay - 0.001)
        XCTAssertNotNil(projection.crossing)
        XCTAssertEqual(projection.crossing!.value, 80, accuracy: 0.05)
    }

    func testScientificProjectionTempersAggressiveObservedLoss() throws {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Lose ~2 kg/week observed (too fast)
        let samples = [
            HealthMetricSample(value: 100, date: now.addingTimeInterval(-day * 14)),
            HealthMetricSample(value: 96, date: now.addingTimeInterval(-day * 7)),
            HealthMetricSample(value: 92, date: now)
        ]
        let projection = try XCTUnwrap(
            HealthChartMath.scientificProjectWeight(
                samples: samples,
                idealKg: 80,
                currentKg: 92,
                heightCm: 180,
                sex: .male,
                now: now
            )
        )
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 92) / 7.0
        XCTAssertGreaterThanOrEqual(projection.temperedSlopeKgPerDay, -safe - 0.002)
        XCTAssertTrue(projection.notes.contains(where: { $0.lowercased().contains("tempered") || $0.lowercased().contains("safe") }))
    }

    func testScientificProjectionFemaleGainTowardTarget() throws {
        let day: TimeInterval = 86_400
        let now = Date()
        let samples = [
            HealthMetricSample(value: 48, date: now.addingTimeInterval(-day * 21)),
            HealthMetricSample(value: 48.2, date: now.addingTimeInterval(-day * 10)),
            HealthMetricSample(value: 48.1, date: now)
        ]
        let target = TargetFeasibility.weightKg(forBMI: 20, heightCm: 165)
        let projection = try XCTUnwrap(
            HealthChartMath.scientificProjectWeight(
                samples: samples,
                idealKg: target,
                currentKg: 48.1,
                heightCm: 165,
                sex: .female,
                now: now
            )
        )
        XCTAssertGreaterThan(projection.temperedSlopeKgPerDay, 0)
        XCTAssertNotNil(projection.crossing)
    }

    @MainActor
    func testProcessCoachStatedTargetsUpdatesProfile() {
        let session = ScaleSessionViewModel()
        session.profile = maleProfile()
        let before = session.profile.idealWeightKg
        let results = session.processCoachStatedTargets(from: "Aim for 82 kg please")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(session.profile.idealWeightKg, 82, accuracy: 0.01)
        XCTAssertNotEqual(before, 82)
    }

    @MainActor
    func testProcessCoachRejectsDoesNotUpdateFatTarget() {
        let session = ScaleSessionViewModel()
        session.profile = maleProfile()
        session.profile.idealBodyFatPercent = 18
        _ = session.processCoachStatedTargets(from: "I want 4% body fat")
        XCTAssertEqual(session.profile.idealBodyFatPercent, 18)
    }
}
