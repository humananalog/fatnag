import UIKit
import XCTest
@testable import TheScale

final class MonthlyHeroTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func sample(_ kg: Double, _ year: Int, _ month: Int, _ day: Int) -> MonthlyWeighSample {
        MonthlyWeighSample(kg: kg, date: date(year, month, day))
    }

    func testOffersOnlyOnTheFirst() {
        let firstMorning = date(2026, 10, 1, 7)
        let firstNight = date(2026, 10, 1, 23)
        let second = date(2026, 10, 2, 7)
        XCTAssertTrue(MonthlyHeroEngine.shouldOfferAfterWeighIn(now: firstMorning, calendar: calendar))
        XCTAssertTrue(MonthlyHeroEngine.shouldOfferAfterWeighIn(now: firstNight, calendar: calendar))
        XCTAssertFalse(MonthlyHeroEngine.shouldOfferAfterWeighIn(now: second, calendar: calendar))
    }

    func testLiveInsightIsPlusAndProOnly() {
        XCTAssertFalse(MonthlyHeroEngine.allowsLiveInsight(plan: .free))
        XCTAssertTrue(MonthlyHeroEngine.allowsLiveInsight(plan: .plus))
        XCTAssertTrue(MonthlyHeroEngine.allowsLiveInsight(plan: .pro))
    }

    func testJuneLossIsMangoesAndNotDecember() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(70.0, 2026, 5, 3),
                sample(69.6, 2026, 5, 10),
                sample(69.2, 2026, 5, 18),
                sample(68.9, 2026, 5, 27),
            ],
            weighInKg: 68.8,
            idealKg: 62,
            name: "Alex",
            now: date(2026, 6, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .ready)
        XCTAssertEqual(facts.direction, .loss)
        XCTAssertEqual(facts.visual, .graph)
        XCTAssertEqual(facts.festivalEmoji, "☀️")
        XCTAssertEqual(facts.festivalTitle, "Long light")
        XCTAssertEqual(facts.unit?.phrase, "4 mangoes")
        XCTAssertTrue(facts.canAskKeel)
        XCTAssertNil(facts.medicalNote)
        XCTAssertTrue(facts.monthlyAction.contains("evening is still bright") || facts.monthlyAction.contains("long light") || facts.monthlyAction.contains("same plate"))
        XCTAssertFalse(facts.festivalTitle.contains("Festive"))
        XCTAssertFalse(facts.monthlyAction.contains("festive"))
    }

    func testDecemberCardIsNotAJuneCard() {
        let june = MonthlyHeroEngine.compose(
            samples: [
                sample(70.0, 2026, 5, 3),
                sample(69.4, 2026, 5, 12),
                sample(69.0, 2026, 5, 20),
                sample(68.9, 2026, 5, 28),
            ],
            weighInKg: 68.8,
            idealKg: 62,
            name: "Alex",
            now: date(2026, 6, 1),
            calendar: calendar
        )
        let december = MonthlyHeroEngine.compose(
            samples: [
                sample(70.0, 2026, 11, 3),
                sample(69.4, 2026, 11, 12),
                sample(69.0, 2026, 11, 20),
                sample(68.9, 2026, 11, 28),
            ],
            weighInKg: 68.8,
            idealKg: 62,
            name: "Alex",
            now: date(2026, 12, 1),
            calendar: calendar
        )
        XCTAssertNotEqual(june.festivalTitle, december.festivalTitle)
        XCTAssertNotEqual(june.festivalEmoji, december.festivalEmoji)
        XCTAssertNotEqual(june.monthlyAction, december.monthlyAction)
        XCTAssertEqual(december.festivalTitle, "Festive, not feral")
        XCTAssertEqual(december.unit?.emoji, "🍊")
        XCTAssertTrue(december.monthlyAction.contains("festive"))
        XCTAssertFalse(june.ruleInsight.contains("festive"))
    }

    func testAprilRiceBowls() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(80.0, 2026, 3, 2),
                sample(79.7, 2026, 3, 10),
                sample(79.5, 2026, 3, 18),
                sample(79.3, 2026, 3, 27),
            ],
            weighInKg: 79.1,
            idealKg: 72,
            name: "Sam",
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.direction, .loss)
        XCTAssertEqual(facts.unit?.phrase, "5 bowls of rice")
        XCTAssertEqual(facts.festivalTitle, "April, honestly")
        XCTAssertTrue(facts.sinceLine.contains("March"))
    }

    func testOctoberPumpkins() {
        let unit = MonthlyHeroEngine.relatableUnit(absKg: 1.8, month: 10)
        XCTAssertEqual(unit?.phrase, "2 small pumpkins")
        XCTAssertEqual(unit?.emoji, "🎃")
    }

    func testNewUserHasNoInventedDelta() {
        let facts = MonthlyHeroEngine.compose(
            samples: [],
            weighInKg: 82.4,
            idealKg: 75,
            name: "Nova",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .brandNew)
        XCTAssertEqual(facts.visual, .bigType)
        XCTAssertNil(facts.deltaKg)
        XCTAssertNil(facts.unit)
        XCTAssertFalse(facts.canAskKeel)
        XCTAssertEqual(facts.bigWord, "DAY ONE")
        XCTAssertTrue(facts.ruleInsight.contains("will not invent"))
        XCTAssertTrue(facts.monthlyAction.contains("weigh most mornings"))
    }

    func testEmptyHistory() {
        let facts = MonthlyHeroEngine.compose(
            samples: [],
            weighInKg: nil,
            idealKg: nil,
            name: "",
            now: date(2026, 1, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .noHistory)
        XCTAssertEqual(facts.visual, .bigType)
        XCTAssertNil(facts.deltaKg)
        XCTAssertTrue(facts.ruleInsight.contains("refuses to fake"))
        XCTAssertEqual(facts.festivalEmoji, "🎆")
    }

    func testBadRecordsAreDroppedAndRecovered() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(80.0, 2026, 9, 2),
                sample(0, 2026, 9, 3),
                sample(400, 2026, 9, 4),
                sample(140, 2026, 9, 8),
                sample(79.4, 2026, 9, 12),
                sample(79.0, 2026, 9, 20),
                sample(78.6, 2026, 9, 28),
            ],
            weighInKg: 78.2,
            idealKg: 72,
            name: "Alex",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .ready)
        XCTAssertGreaterThanOrEqual(facts.rejectedSampleCount, 3)
        XCTAssertEqual(facts.direction, .loss)
        XCTAssertNotNil(facts.deltaKg)
        XCTAssertTrue(facts.ruleInsight.contains("nonsense") || facts.rejectedSampleCount > 0)
        XCTAssertLessThan(facts.deltaKg ?? 0, 0)
        XCTAssertGreaterThan(facts.priorKg ?? 0, 70)
        XCTAssertLessThan(facts.priorKg ?? 999, 90)
    }

    func testAllJunkIsBadRecords() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(4, 2026, 9, 2),
                sample(12, 2026, 9, 10),
                sample(500, 2026, 9, 20),
                MonthlyWeighSample(kg: .nan, date: date(2026, 9, 21)),
            ],
            weighInKg: nil,
            idealKg: 70,
            name: "Alex",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .badRecords)
        XCTAssertEqual(facts.visual, .bigType)
        XCTAssertNil(facts.deltaKg)
        XCTAssertFalse(facts.canAskKeel)
        XCTAssertTrue(facts.monthlyAction.contains("clean morning weigh"))
    }

    func testIncompleteWhenLastMonthMissing() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(81, 2026, 1, 4),
                sample(80, 2026, 1, 18),
            ],
            weighInKg: 79.5,
            idealKg: 72,
            name: "Alex",
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .incomplete)
        XCTAssertNil(facts.deltaKg)
        XCTAssertEqual(facts.visual, .bigType)
        XCTAssertTrue(facts.ruleInsight.contains("too thin"))
        XCTAssertTrue(facts.monthlyAction.contains("four morning weighs"))
    }

    func testStableMonthUsesTheLine() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(75.0, 2026, 3, 2),
                sample(75.1, 2026, 3, 9),
                sample(74.9, 2026, 3, 16),
                sample(75.0, 2026, 3, 24),
            ],
            weighInKg: 75.05,
            idealKg: 75.0,
            name: "Alex",
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.edge, .ready)
        XCTAssertEqual(facts.direction, .stable)
        XCTAssertEqual(facts.visual, .graph)
        XCTAssertEqual(facts.intent, .maintain)
        XCTAssertNil(facts.unit)
        XCTAssertNil(facts.medicalNote)
        XCTAssertTrue(facts.monthlyAction.contains("leave the plan alone"))
        XCTAssertTrue(facts.bigWord == "STEADY")
    }

    func testFastLossCarriesClinicianNote() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(84.0, 2026, 9, 2),
                sample(82.4, 2026, 9, 10),
                sample(81.2, 2026, 9, 18),
                sample(80.4, 2026, 9, 26),
            ],
            weighInKg: 80.2,
            idealKg: 74,
            name: "Alex",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.direction, .loss)
        XCTAssertEqual(facts.pace, .fastLoss)
        XCTAssertNotNil(facts.medicalNote)
        XCTAssertTrue(facts.medicalNote?.contains("clinician") == true)
        XCTAssertTrue(facts.monthlyAction.contains("clinician"))
        XCTAssertTrue(facts.ruleInsight.contains("sprint") || facts.ruleInsight.contains("jog"))
    }

    func testModestGainWhileCuttingDoesNotDiagnose() {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(70.0, 2026, 3, 2),
                sample(70.2, 2026, 3, 12),
                sample(70.4, 2026, 3, 20),
                sample(70.6, 2026, 3, 28),
            ],
            weighInKg: 71.2,
            idealKg: 65,
            name: "Alex",
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertEqual(facts.direction, .gain)
        XCTAssertEqual(facts.intent, .lose)
        XCTAssertEqual(facts.pace, .calm)
        XCTAssertNil(facts.medicalNote)
        XCTAssertTrue(facts.ruleInsight.contains("Not a verdict"))
        XCTAssertTrue(facts.monthlyAction.contains("walk"))
        XCTAssertFalse(facts.monthlyAction.contains("clinician"))
    }

    func testShareDeltaGluesGramsAndKeepsKilogramsSpaced() {
        let grams = MonthlyHeroEngine.compose(
            samples: [
                sample(80.0, 2026, 3, 2),
                sample(79.8, 2026, 3, 12),
                sample(79.7, 2026, 3, 20),
                sample(79.6, 2026, 3, 28),
            ],
            weighInKg: 79.6,
            idealKg: 72,
            name: "Sam",
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertEqual(MonthlyHeroShareCopy.delta(facts: grams, units: .metric), "−400g")
        XCTAssertEqual(MonthlyHeroShareCopy.delta(facts: grams, units: .imperial).contains(" "), true)

        let kilos = MonthlyHeroEngine.compose(
            samples: [
                sample(92.4, 2026, 9, 2),
                sample(91.0, 2026, 9, 12),
                sample(89.4, 2026, 9, 20),
                sample(88.2, 2026, 9, 28),
            ],
            weighInKg: 87.6,
            idealKg: 78,
            name: "Bob",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        let metric = MonthlyHeroShareCopy.delta(facts: kilos, units: .metric)
        XCTAssertTrue(metric.contains(" kg"), metric)
        XCTAssertFalse(metric.hasSuffix("g") && !metric.contains(" "), metric)
    }

    func testSharePosterIsWhatsAppPortraitJPEG() async {
        let facts = MonthlyHeroEngine.compose(
            samples: [
                sample(92.4, 2026, 9, 2),
                sample(91.0, 2026, 9, 12),
                sample(89.4, 2026, 9, 20),
                sample(88.2, 2026, 9, 28),
            ],
            weighInKg: 87.6,
            idealKg: 78,
            name: "Bob",
            now: date(2026, 10, 1),
            calendar: calendar
        )
        let item = await MainActor.run {
            MonthlyHeroShareRenderer.render(
                facts: facts,
                insight: facts.ruleInsight,
                universe: .glacierForge,
                units: .metric
            )
        }
        let image = item.flatMap { UIImage(data: $0.jpeg) }
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width ?? 0, MonthlyHeroShareCanvas.pixelSize.width, accuracy: 1)
        XCTAssertEqual(image?.size.height ?? 0, MonthlyHeroShareCanvas.pixelSize.height, accuracy: 1)
        XCTAssertEqual(Double(MonthlyHeroShareCanvas.pixelSize.width / MonthlyHeroShareCanvas.pixelSize.height), 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(item?.jpeg.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertGreaterThan(item?.jpeg.count ?? 0, 20_000)
        XCTAssertEqual(item?.filename, "fatnag-2026-10.jpg")
        XCTAssertTrue(item?.message.contains("−") == true)
    }

    func testFestivalTitlesAreUniqueAcrossTheYear() {
        var seen = Set<String>()
        for month in 1...12 {
            let fest = MonthlyHeroEngine.festival(for: month)
            XCTAssertTrue(seen.insert(fest.title).inserted, "Duplicate festival title \(fest.title)")
            XCTAssertFalse(fest.emoji.isEmpty)
        }
    }
}

#if DEBUG
final class DemoRealUserSnapshotTests: XCTestCase {
    func testBobAndAliceCanReturnToTheRealProfile() {
        let defaults = UserDefaults.standard
        let stash = DemoRealUserSnapshot.captureRaw()
        let priorSnapshot = defaults.object(forKey: DemoRealUserSnapshot.storageKey)
        defer {
            DemoRealUserSnapshot.apply(stash)
            if let priorSnapshot {
                defaults.set(priorSnapshot, forKey: DemoRealUserSnapshot.storageKey)
            } else {
                defaults.removeObject(forKey: DemoRealUserSnapshot.storageKey)
            }
        }

        defaults.removeObject(forKey: DemoRealUserSnapshot.storageKey)
        var real = UserBodyProfile.default
        real.displayName = "Real Pat"
        UserProfileStore.save(real)

        DemoPersonaSeeder.persist(.male)
        XCTAssertEqual(UserProfileStore.load().displayName, "Bob")
        XCTAssertEqual(DemoRealUserSnapshot.displayName, "Real Pat")
        XCTAssertTrue(DemoRealUserSnapshot.canRestore)

        DemoPersonaSeeder.persist(.female)
        XCTAssertEqual(UserProfileStore.load().displayName, "Alice")
        XCTAssertEqual(DemoRealUserSnapshot.displayName, "Real Pat")

        XCTAssertTrue(DemoRealUserSnapshot.restore())
        XCTAssertEqual(UserProfileStore.load().displayName, "Real Pat")
        XCTAssertTrue(DemoRealUserSnapshot.canRestore)
        XCTAssertEqual(DemoRealUserSnapshot.displayName, "Real Pat")
    }

    func testAliceIsNeverTheReturnTarget() {
        let defaults = UserDefaults.standard
        let stash = DemoRealUserSnapshot.captureRaw()
        let priorSnapshot = defaults.object(forKey: DemoRealUserSnapshot.storageKey)
        defer {
            DemoRealUserSnapshot.apply(stash)
            if let priorSnapshot {
                defaults.set(priorSnapshot, forKey: DemoRealUserSnapshot.storageKey)
            } else {
                defaults.removeObject(forKey: DemoRealUserSnapshot.storageKey)
            }
        }

        defaults.removeObject(forKey: DemoRealUserSnapshot.storageKey)
        var alice = UserBodyProfile.default
        alice.displayName = "Alice"
        alice.sex = .female
        alice.heightCm = 165
        alice.ageYears = 29
        UserProfileStore.save(alice)

        DemoPersonaSeeder.persist(.male)
        XCTAssertFalse(DemoRealUserSnapshot.canRestore)
        XCTAssertNotEqual(DemoRealUserSnapshot.displayName, "Alice")

        var alex = UserBodyProfile.default
        alex.displayName = "Alex"
        alex.sex = .male
        alex.heightCm = 175
        alex.ageYears = 35
        UserProfileStore.save(alex)
        DemoPersonaSeeder.persist(.female)
        XCTAssertEqual(DemoRealUserSnapshot.displayName, "Alex")
        XCTAssertEqual(UserProfileStore.load().displayName, "Alice")
        XCTAssertTrue(DemoRealUserSnapshot.restore())
        XCTAssertEqual(UserProfileStore.load().displayName, "Alex")
    }
}
#endif
