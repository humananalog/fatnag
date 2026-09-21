import Foundation

/// Local energy-balance read: compares observed weight trajectory to expected deficit
/// given BMR + HealthKit activity. No cloud. Coaching heuristic only.
enum WeeklyEnergyDiagnosis: Equatable, Sendable {
    /// Moving enough, but weight stalled / rose vs expected cut → intake too high.
    case overeatingWhileActive(
        impliedDailyIntakeKcal: Int,
        estimatedDailySpendKcal: Int,
        targetMaxKcal: Int,
        expectedDeltaKg: Double,
        observedDeltaKg: Double,
        windowDays: Double
    )
    /// Soft activity and stalled / behind on a cut.
    case underMoving(
        estimatedDailySpendKcal: Int,
        expectedDeltaKg: Double,
        observedDeltaKg: Double,
        windowDays: Double
    )
    /// Trajectory roughly matches the weekly mini-goal pace.
    case onPace(
        expectedDeltaKg: Double,
        observedDeltaKg: Double,
        windowDays: Double
    )
    /// Losing faster than the paced goal (still report; advice stays gentle).
    case aheadOfEnergy(
        expectedDeltaKg: Double,
        observedDeltaKg: Double,
        windowDays: Double
    )
    case insufficientData
}

struct WeeklyEnergyBalanceSnapshot: Equatable, Sendable {
    var diagnosis: WeeklyEnergyDiagnosis
    var estimatedDailySpendKcal: Int?
    var impliedDailyIntakeKcal: Int?
    var isMeaningfullyActive: Bool
    var summaryLine: String
}

/// Pure local evaluator: historical mass + activity → overeating vs under-moving.
enum WeeklyEnergyBalanceEvaluator {
    static let kcalPerKg: Double = 7700

    /// Active enough that a stall is unlikely to be "didn't move".
    static func isMeaningfullyActive(
        digest: FitnessDigest?,
        estimatedActiveKcalPerDay: Double
    ) -> Bool {
        let steps = digest?.stepsToday ?? 0
        let todayActive = digest?.activeEnergyKcalToday ?? 0
        let km7 = digest?.walkingRunningDistance?.distanceKmLast7d ?? 0
        let workouts = digest?.workoutCountLast24h ?? 0
        if steps >= 6_500 { return true }
        if todayActive >= 280 { return true }
        if estimatedActiveKcalPerDay >= 280 { return true }
        if km7 >= 28 { return true }
        if workouts >= 1 { return true }
        return false
    }

    /// BMR + active energy (7d avg preferred, else today, else NEAT from steps/distance).
    static func estimatedDailySpendKcal(
        profile: UserBodyProfile,
        weightKg: Double,
        digest: FitnessDigest?
    ) -> Double {
        let bmr = WeeklyGoalSurfaceEngine.mifflinBMR(profile: profile, weightKg: weightKg)
        if let avg7 = digest?.activeEnergyKcalLast7dAverage, avg7 > 0 {
            return bmr + avg7
        }
        if let today = digest?.activeEnergyKcalToday, today > 0 {
            return bmr + today
        }
        // NEAT proxy when Health active-energy is thin.
        let steps = digest?.stepsToday ?? 0
        let km7 = digest?.walkingRunningDistance?.distanceKmLast7d ?? 0
        let neatFromSteps = steps * 0.04 // ~0.04 kcal/step ballpark
        let neatFromKm = (km7 / 7.0) * 55 // ~55 kcal/km walking ballpark
        let neat = max(neatFromSteps, neatFromKm, 180)
        return bmr + neat
    }

    /// Prefer multi-day Health weights; fall back to week-start → current.
    static func weightWindow(
        recentWeights: [HealthWeightSample],
        weekStartKg: Double?,
        weekStartDate: Date?,
        currentKg: Double?,
        now: Date,
        calendar: Calendar = .current
    ) -> (startKg: Double, endKg: Double, days: Double)? {
        let sorted = recentWeights.sorted { $0.date < $1.date }
        let cutoff = now.addingTimeInterval(-8 * 86_400)
        let window = sorted.filter { $0.date >= cutoff }
        if window.count >= 2 {
            let first = window.first!
            let last = window.last!
            let days = max(1.0, last.date.timeIntervalSince(first.date) / 86_400)
            if days >= 2.0 {
                return (first.weightKg, last.weightKg, days)
            }
        }
        if let start = weekStartKg, let startDate = weekStartDate, let end = currentKg {
            let days = max(1.0, now.timeIntervalSince(startDate) / 86_400)
            if days >= 2.0 {
                return (start, end, days)
            }
        }
        return nil
    }

    static func evaluate(
        profile: UserBodyProfile,
        weeklyGoal: WeeklyMiniGoal,
        currentKg: Double?,
        recentWeights: [HealthWeightSample],
        digest: FitnessDigest?,
        targetMaxKcal: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyEnergyBalanceSnapshot {
        let weight = currentKg ?? weeklyGoal.weekStartKg ?? profile.idealWeightKg
        let spend = estimatedDailySpendKcal(profile: profile, weightKg: weight, digest: digest)
        let activeKcal: Double = {
            if let avg = digest?.activeEnergyKcalLast7dAverage { return avg }
            return digest?.activeEnergyKcalToday ?? max(0, spend - WeeklyGoalSurfaceEngine.mifflinBMR(profile: profile, weightKg: weight))
        }()
        let active = isMeaningfullyActive(digest: digest, estimatedActiveKcalPerDay: activeKcal)

        guard let window = weightWindow(
            recentWeights: recentWeights,
            weekStartKg: weeklyGoal.weekStartKg,
            weekStartDate: weeklyGoal.weekStartDate,
            currentKg: currentKg,
            now: now,
            calendar: calendar
        ) else {
            return WeeklyEnergyBalanceSnapshot(
                diagnosis: .insufficientData,
                estimatedDailySpendKcal: Int(spend.rounded()),
                impliedDailyIntakeKcal: nil,
                isMeaningfullyActive: active,
                summaryLine: "Need a few weigh-ins before energy balance can talk."
            )
        }

        let observed = window.endKg - window.startKg
        // Target daily energy change from weekly mini-goal (negative = deficit).
        let targetDailyDeltaKcal = (weeklyGoal.targetDeltaKg * kcalPerKg) / 7.0
        let expected = (targetDailyDeltaKcal * window.days) / kcalPerKg
        // Implied intake from energy + observed mass change.
        let implied = spend + (observed * kcalPerKg) / window.days

        let cutting = weeklyGoal.targetDeltaKg < -0.12
        let stallSlack = max(0.12, abs(expected) * 0.45)
        let stalledOrWorse = observed > expected + stallSlack
        // Soft stall: almost flat while expecting a real cut.
        let softStall = cutting && observed > -0.08 && expected < -0.15 && window.days >= 3

        let diagnosis: WeeklyEnergyDiagnosis
        if cutting && (stalledOrWorse || softStall) && active && implied > Double(targetMaxKcal) + 80 {
            diagnosis = .overeatingWhileActive(
                impliedDailyIntakeKcal: Int(implied.rounded()),
                estimatedDailySpendKcal: Int(spend.rounded()),
                targetMaxKcal: targetMaxKcal,
                expectedDeltaKg: expected,
                observedDeltaKg: observed,
                windowDays: window.days
            )
        } else if cutting && (stalledOrWorse || softStall) && !active {
            diagnosis = .underMoving(
                estimatedDailySpendKcal: Int(spend.rounded()),
                expectedDeltaKg: expected,
                observedDeltaKg: observed,
                windowDays: window.days
            )
        } else if observed < expected - stallSlack {
            diagnosis = .aheadOfEnergy(
                expectedDeltaKg: expected,
                observedDeltaKg: observed,
                windowDays: window.days
            )
        } else {
            diagnosis = .onPace(
                expectedDeltaKg: expected,
                observedDeltaKg: observed,
                windowDays: window.days
            )
        }

        let summary: String = {
            switch diagnosis {
            case .overeatingWhileActive(let intake, let spendK, let maxK, let exp, let obs, let days):
                return String(
                    format: "Active ~%d kcal/day spend, implied intake ~%d vs max %d. %.1fd weight %+.2f kg (pace wanted %+.2f).",
                    spendK, intake, maxK, days, obs, exp
                )
            case .underMoving(_, let exp, let obs, let days):
                return String(
                    format: "Soft movement + %.1fd weight %+.2f kg (pace wanted %+.2f). Move more or eat less.",
                    days, obs, exp
                )
            case .onPace(let exp, let obs, let days):
                return String(format: "On energy pace: %.1fd %+.2f kg (wanted %+.2f).", days, obs, exp)
            case .aheadOfEnergy(let exp, let obs, let days):
                return String(format: "Ahead of energy pace: %.1fd %+.2f kg (wanted %+.2f).", days, obs, exp)
            case .insufficientData:
                return "Thin weight history for energy balance."
            }
        }()

        return WeeklyEnergyBalanceSnapshot(
            diagnosis: diagnosis,
            estimatedDailySpendKcal: Int(spend.rounded()),
            impliedDailyIntakeKcal: Int(implied.rounded()),
            isMeaningfullyActive: active,
            summaryLine: summary
        )
    }

    /// Diet-aware meal line that respects the daily max kcal / protein hit.
    static func mealSuggestion(
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int
    ) -> String {
        switch diet {
        case .vegan:
            return "Meals: tofu scramble + berries; lentil bowl + greens; apple. Cap \(maxKcal) kcal, hit \(proteinGrams) g protein."
        case .vegetarian:
            return "Meals: eggs + spinach; greek yogurt; bean chili. Cap \(maxKcal) kcal, hit \(proteinGrams) g protein."
        case .pescatarian:
            return "Meals: egg whites + fruit; tuna salad; salmon + broccoli. Cap \(maxKcal) kcal, hit \(proteinGrams) g protein."
        case .omnivore, .other:
            return "Meals: eggs + fruit; chicken salad; lean fish + veg. Cap \(maxKcal) kcal, hit \(proteinGrams) g protein. Close the kitchen after."
        }
    }
}
