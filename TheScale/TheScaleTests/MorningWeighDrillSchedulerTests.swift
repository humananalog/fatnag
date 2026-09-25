import XCTest
@testable import TheScale

final class MorningWeighDrillSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return cal
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    func testFallbackSchedulesTodayWhenStillBeforeClock() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFallbackRollsTomorrowWhenPastClock() {
        let now = date(year: 2026, month: 9, day: 23, hour: 8, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFallbackRollsTomorrowWhenPastNine() {
        let now = date(year: 2026, month: 9, day: 23, hour: 9, minute: 5)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
    }

    func testFallbackClampsHourAtOrAfterNineToBeforeNine() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 10,
            minute: 0,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 59)
    }

    func testFallbackRollsTomorrowWhenAlreadyWeighed() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: true,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
    }

    func testFallbackRollsTomorrowWhenAlreadyFired() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: true,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day], from: fire)
        XCTAssertEqual(comps.day, 24)
    }

    func testPendingFireMatchesIntended() {
        let intended = date(year: 2026, month: 9, day: 24, hour: 7, minute: 30)
        XCTAssertTrue(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(
                pending: intended.addingTimeInterval(5),
                intended: intended
            )
        )
        XCTAssertFalse(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(
                pending: intended.addingTimeInterval(120),
                intended: intended
            )
        )
        XCTAssertFalse(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(pending: nil, intended: intended)
        )
    }

    func testFallbackPastNineUsesTomorrowLocalMorning() {
        // 21:46 HKT on Sep 23 → next slot is Sep 24 07:30 HKT (= Sep 23 23:30 UTC).
        let now = date(year: 2026, month: 9, day: 23, hour: 21, minute: 46)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar,
            forceTomorrow: true
        )
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
        // Absolute instant must be 2026-09-23 23:30 UTC when TZ is HKT.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = utcCal.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(utc.day, 23)
        XCTAssertEqual(utc.hour, 23)
        XCTAssertEqual(utc.minute, 30)
    }

    func testDetectWeighInTodayFromRecentHealth() {
        let now = date(year: 2026, month: 9, day: 23, hour: 10, minute: 0)
        let sample = HealthWeightSample(id: UUID(), weightKg: 80, date: now)
        XCTAssertTrue(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [sample],
                now: now,
                calendar: calendar
            )
        )
        let yesterday = date(year: 2026, month: 9, day: 22, hour: 8, minute: 0)
        let old = HealthWeightSample(id: UUID(), weightKg: 80, date: yesterday)
        XCTAssertFalse(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [old],
                now: now,
                calendar: calendar
            )
        )
        let junk = HealthWeightSample(id: UUID(), weightKg: 0, date: now)
        XCTAssertFalse(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [junk],
                now: now,
                calendar: calendar
            )
        )
    }

    func testDetectWeighInTodayHonorsLocalDayStampWithoutHealth() {
        let now = date(year: 2026, month: 9, day: 23, hour: 10, minute: 0)
        let stamp = ScaleSessionViewModel.localDayStamp(now, calendar: calendar)
        XCTAssertTrue(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [],
                localDayStamp: stamp,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [],
                localDayStamp: "2026-09-22",
                now: now,
                calendar: calendar
            )
        )
    }

    func testDetectWeighInTodayFromHealthEvenWithoutStamp() {
        let now = date(year: 2026, month: 9, day: 24, hour: 14, minute: 0)
        let sample = HealthMetricSample(value: 81.2, date: now)
        XCTAssertTrue(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [sample],
                trendWeights: [],
                recentWeights: [],
                localDayStamp: nil,
                now: now,
                calendar: calendar
            ),
            "Health today sample must hide Weigh Now even when local stamp is missing"
        )
    }

    func testAutoPresentRequiresStablePlausibleAndNotWeighed() {
        XCTAssertTrue(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: false,
                isAutoPresenting: false,
                alreadyWeighedToday: false,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: false,
                measurementStabilized: true,
                weightKg: 78.2,
                phaseAllowsAutoOpen: true
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: false,
                isAutoPresenting: false,
                alreadyWeighedToday: false,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: false,
                measurementStabilized: false,
                weightKg: 78.2,
                phaseAllowsAutoOpen: true
            ),
            "Unstable ad blips must not open the sheet"
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: false,
                isAutoPresenting: false,
                alreadyWeighedToday: true,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: false,
                measurementStabilized: true,
                weightKg: 78.2,
                phaseAllowsAutoOpen: true
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: false,
                isAutoPresenting: false,
                alreadyWeighedToday: false,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: true,
                measurementStabilized: true,
                weightKg: 78.2,
                phaseAllowsAutoOpen: true
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: false,
                isAutoPresenting: false,
                alreadyWeighedToday: false,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: false,
                measurementStabilized: true,
                weightKg: 0,
                phaseAllowsAutoOpen: true
            )
        )
        XCTAssertFalse(
            ScaleSessionViewModel.shouldAutoPresentLiveSheet(
                isAlreadyPresented: true,
                isAutoPresenting: false,
                alreadyWeighedToday: false,
                purpose: .normal,
                isEditingDraft: false,
                cooldownActive: false,
                measurementStabilized: true,
                weightKg: 78.2,
                phaseAllowsAutoOpen: true
            ),
            "No double-present"
        )
    }

    func testNotificationPreferencesDefaultMorningDrillOn() {
        let prefs = NotificationPreferences.default
        XCTAssertTrue(prefs.morningWeighDrill)
        XCTAssertTrue(prefs.notifyOnBadTrend)
        XCTAssertTrue(prefs.weeklyGoalReminders)
        XCTAssertEqual(prefs.morningWeighFallbackHour, 7)
        XCTAssertEqual(prefs.morningWeighFallbackMinute, 30)
    }

    func testNotificationPreferencesDecodesMissingFallbackKeys() throws {
        let json = """
        {"notifyOnBadTrend":true,"weeklyGoalReminders":true,"morningWeighDrill":true}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        XCTAssertEqual(prefs.morningWeighFallbackHour, 7)
        XCTAssertEqual(prefs.morningWeighFallbackMinute, 30)
        XCTAssertTrue(prefs.morningWeighDrill)
    }
}

final class ProfileNumericBoundsTests: XCTestCase {
    func testAgeClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampAgeYears(17).value, 18)
        XCTAssertEqual(ProfileNumericBounds.clampAgeYears(101).value, 100)
        XCTAssertFalse(ProfileNumericBounds.clampAgeYears(30).didClamp)
    }

    func testHeightClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampHeightCm(90).value, 120, accuracy: 0.01)
        XCTAssertEqual(ProfileNumericBounds.clampHeightCm(300).value, 250, accuracy: 0.01)
    }

    func testWeightClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampWeightKg(10).value, 30, accuracy: 0.01)
        XCTAssertEqual(ProfileNumericBounds.clampWeightKg(400).value, 300, accuracy: 0.01)
    }

    func testPlausibleWeighKgRejectsZeroAndOutOfBounds() {
        XCTAssertFalse(ProfileNumericBounds.isPlausibleWeighKg(0))
        XCTAssertFalse(ProfileNumericBounds.isPlausibleWeighKg(-1))
        XCTAssertFalse(ProfileNumericBounds.isPlausibleWeighKg(10))
        XCTAssertFalse(ProfileNumericBounds.isPlausibleWeighKg(400))
        XCTAssertFalse(ProfileNumericBounds.isPlausibleWeighKg(.nan))
        XCTAssertTrue(ProfileNumericBounds.isPlausibleWeighKg(70))
        XCTAssertNotNil(ProfileNumericBounds.rejectWeighKgMessage(0))
        XCTAssertNil(ProfileNumericBounds.rejectWeighKgMessage(72.4))
    }

    func testBodyFatOptional() {
        XCTAssertNil(ProfileNumericBounds.clampOptionalBodyFatPercent(nil).value)
        XCTAssertNil(ProfileNumericBounds.clampOptionalBodyFatPercent(0).value)
        XCTAssertEqual(ProfileNumericBounds.clampOptionalBodyFatPercent(18).value ?? -1, 18, accuracy: 0.01)
        let high = ProfileNumericBounds.clampOptionalBodyFatPercent(90)
        XCTAssertEqual(high.value ?? -1, 60, accuracy: 0.01)
        XCTAssertNotNil(high.message)
    }

    func testMorningFallbackClamp() {
        let late = ProfileNumericBounds.clampMorningFallback(hour: 10, minute: 0)
        XCTAssertEqual(late.hour, 8)
        XCTAssertEqual(late.minute, 59)
        let ok = ProfileNumericBounds.clampMorningFallback(hour: 7, minute: 30)
        XCTAssertEqual(ok.hour, 7)
        XCTAssertEqual(ok.minute, 30)
    }

    func testIdealWeightClampUsesSexAgeBMIBand() {
        // 40 kg at 170 cm is BMI ~13.8 — below female floor.
        let thin = ProfileNumericBounds.clampIdealWeightKg(
            40,
            heightCm: 170,
            currentKg: 70,
            sex: .female,
            ageYears: 28
        )
        XCTAssertTrue(thin.didClamp)
        XCTAssertGreaterThan(thin.value, 40)
        let floorBMI = TargetFeasibility.targetBMIHardFloor(sex: .female, ageYears: 28)
        let expectedFloor = TargetFeasibility.weightKg(forBMI: floorBMI, heightCm: 170)
        XCTAssertEqual(thin.value, expectedFloor, accuracy: 0.15)
        XCTAssertNotNil(thin.message)

        // Sensible mid-band target should pass through.
        let ok = ProfileNumericBounds.clampIdealWeightKg(
            62,
            heightCm: 170,
            currentKg: 70,
            sex: .female,
            ageYears: 28
        )
        XCTAssertFalse(ok.didClamp)
        XCTAssertEqual(ok.value, 62, accuracy: 0.01)
    }

    func testDreamBoundsNeverBelowSexAgeBMIFloor() {
        let bounds = GoalPaceGuard.dreamWeightBoundsKg(
            currentKg: 55,
            heightCm: 165,
            sex: .female,
            ageYears: 70
        )
        let floorBMI = TargetFeasibility.targetBMIHardFloor(sex: .female, ageYears: 70)
        let floorKg = TargetFeasibility.weightKg(forBMI: floorBMI, heightCm: 165)
        XCTAssertEqual(floorBMI, 18.5, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(bounds.lowerBound, floorKg - 0.05)
        XCTAssertLessThanOrEqual(bounds.upperBound, TargetFeasibility.weightKg(forBMI: 35, heightCm: 165) + 0.05)
    }

    func testMaleYoungAdultFloorLowerThanElderlyFemale() {
        let maleYoung = TargetFeasibility.targetBMIHardFloor(sex: .male, ageYears: 30)
        let femaleElder = TargetFeasibility.targetBMIHardFloor(sex: .female, ageYears: 70)
        XCTAssertEqual(maleYoung, 16.0, accuracy: 0.01)
        XCTAssertEqual(femaleElder, 18.5, accuracy: 0.01)
        XCTAssertGreaterThan(femaleElder, maleYoung)
    }
}
