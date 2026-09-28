#if DEBUG
import Foundation

/// DEBUG-only demo personas for Simulator promo recordings.
///
/// Launch with:
///   `-demoMale` or `-demoFemale`
/// Optional: `-promoShot=home|weigh|progress|keel` to jump to a capture surface
/// Optional: `-uitesting-skip-splash` (also auto-skipped when a demo flag is present).
///
/// Or Settings → Debug → Load demo (male / female).
///
/// Batch capture: `sites/fatnag-com/scripts/capture-promo-shots.sh`
enum DemoPersonaSeeder {
    enum Persona: String {
        case male
        case female

        var sex: UserBodyProfile.Sex {
            switch self {
            case .male: return .male
            case .female: return .female
            }
        }

        static func fromLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> Persona? {
            if args.contains("-demoFemale") { return .female }
            if args.contains("-demoMale") { return .male }
            return nil
        }
    }

    /// Persist profile + companion stores before `ScaleSessionViewModel` boots (launch args).
    static func persist(_ persona: Persona, now: Date = Date()) {
        let profile = makeProfile(persona, now: now)
        UserProfileStore.save(profile)

        let monday = MondayCardEngine.startOfWeekMonday(now: now)
        let currentKg = currentWeightKg(persona)
        let weekStartKg = roundKg(currentKg + 0.45)
        WeeklyMiniGoalStore.save(
            WeeklyMiniGoal(
                targetDeltaKg: -0.5,
                weekStartKg: weekStartKg,
                weekStartDate: monday,
                title: "Cut 0.5 kg by Sunday"
            )
        )
        MondayCardStore.setPriorSundayTargetKg(weekStartKg + 0.2)

        let dayKey = MealPlanEngine.dayKey(now: now)
        let meals = makeMeals(persona)
        let maxKcal = persona == .male ? 2100 : 1650
        let protein = persona == .male ? 150 : 110
        let fasting = profile.intermittentFasting ?? .noneForCache
        let cacheKey = MealPlanEngine.cacheKey(
            dayKey: dayKey,
            maxKcal: maxKcal,
            proteinGrams: protein,
            diet: profile.dietPreference,
            weeklyDeltaKg: -0.5,
            fasting: fasting,
            now: now
        )
        MealPlanStore.save(
            MealPlanPayload(
                cacheKey: cacheKey,
                dayKey: dayKey,
                maxKcal: maxKcal,
                proteinGrams: protein,
                dietRaw: profile.dietPreference.rawValue,
                meals: meals,
                generatedAt: now,
                usedNetwork: false,
                sourceNote: "Demo meal plan (DEBUG)",
                targetMealCount: meals.count
            )
        )

        CoachChatHistoryStore.save(makeChat(persona, now: now))
        CoachMemoryStore.save(makeMemory(persona, now: now))
        MondayCardStore.save(makeMondayCard(persona, now: now, currentKg: currentKg, weekStartKg: weekStartKg))

        ChartCommentStore.upsert(
            sampleDay: Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now,
            metric: .weight,
            text: persona == .male
                ? "Salt + late dinner. Not fat. Still weigh tomorrow."
                : "Cycle noise. Hold the line, do not panic-cut.",
            now: now
        )

        OnboardingStore.hasCompleted = true
        LegalAcceptanceStore.markAccepted(now: now.addingTimeInterval(-86_400 * 12))
        GrokPrivacyConsent.isAccepted = true
        PreferredUnitSystemStore.save(.metric)
        AppLanguageStore.current = .english
        // Plan override applied on MainActor in hydrate(_:into:).
    }

    /// Fill live session surfaces (history, gauges, flags) after boot.
    @MainActor
    static func hydrate(_ persona: Persona, into session: ScaleSessionViewModel, now: Date = Date()) {
        persist(persona, now: now)

        let profile = makeProfile(persona, now: now)
        let series = makeWeightSeries(persona, now: now)
        let fatSeries = makeBodyFatSeries(persona, now: now)
        let currentKg = series.last?.value ?? currentWeightKg(persona)

        session.applyDemoPersonaPayload(
            profile: profile,
            weeklyGoal: WeeklyMiniGoalStore.load(),
            mealPlan: MealPlanStore.load(),
            mondayCard: MondayCardStore.load(),
            weights: series,
            bodyFat: fatSeries,
            currentKg: currentKg,
            digest: makeDigest(persona, now: now)
        )

        _ = ScaleSubscriptionStore.shared.applyDevPlan(.plus)
    }

    // MARK: - Personas

    private static func makeProfile(_ persona: Persona, now: Date) -> UserBodyProfile {
        let goalDate = Calendar.current.date(byAdding: .month, value: 4, to: now)
        switch persona {
        case .male:
            return UserBodyProfile(
                displayName: "Bob",
                heightCm: 178,
                ageYears: 34,
                sex: .male,
                idealWeightKg: 78,
                goalDate: goalDate,
                idealBodyFatPercent: 15,
                startingWeightKg: 92.4,
                startingBodyFatPercent: 24.5,
                healthContextNotes: "Desk job, lifts 3x/week, likes late espresso.",
                goalDifficultyTitle: "Brat Mode",
                dietPreference: .omnivore,
                location: "Hong Kong",
                ethnicity: "",
                preferredLanguage: "English",
                culturalVibe: "Straight talk. Local cha chaan teng ok.",
                foodAvoidances: "No shellfish",
                foodAvoidancesConfirmed: true,
                useLocalContext: true,
                dietPreferenceConfirmed: true,
                intermittentFasting: .classic168
            )
        case .female:
            return UserBodyProfile(
                displayName: "Alice",
                heightCm: 165,
                ageYears: 29,
                sex: .female,
                idealWeightKg: 58,
                goalDate: goalDate,
                idealBodyFatPercent: 22,
                startingWeightKg: 72.0,
                startingBodyFatPercent: 32.0,
                healthContextNotes: "Runs 2x/week. Hates crash diets.",
                goalDifficultyTitle: "Hell",
                dietPreference: .pescatarian,
                location: "London",
                ethnicity: "",
                preferredLanguage: "English",
                culturalVibe: "Dry humour. No wellness fluff.",
                foodAvoidances: "No peanuts",
                foodAvoidancesConfirmed: true,
                useLocalContext: true,
                dietPreferenceConfirmed: true,
                intermittentFasting: .classic168
            )
        }
    }

    private static func currentWeightKg(_ persona: Persona) -> Double {
        switch persona {
        case .male: return 87.6
        case .female: return 67.4
        }
    }

    private static func startingWeightKg(_ persona: Persona) -> Double {
        switch persona {
        case .male: return 92.4
        case .female: return 72.0
        }
    }

    private static func currentBodyFat(_ persona: Persona) -> Double {
        switch persona {
        case .male: return 20.2
        case .female: return 27.8
        }
    }

    private static func startingBodyFat(_ persona: Persona) -> Double {
        switch persona {
        case .male: return 24.5
        case .female: return 32.0
        }
    }

    // MARK: - Series

    /// ~4 weeks of morning weighs, gentle downtrend with weekend bumps.
    private static func makeWeightSeries(_ persona: Persona, now: Date) -> [HealthMetricSample] {
        let cal = Calendar.current
        let start = startingWeightKg(persona)
        let end = currentWeightKg(persona)
        let days = 28
        var samples: [HealthMetricSample] = []
        for offset in 0..<days {
            let day = days - 1 - offset
            guard let date = cal.date(byAdding: .day, value: -day, to: now) else { continue }
            let morning = cal.date(bySettingHour: 7, minute: 12 + (offset % 7), second: 0, of: date) ?? date
            let t = Double(offset) / Double(max(days - 1, 1))
            let trend = start + (end - start) * t
            let weekday = cal.component(.weekday, from: morning)
            let weekendBump: Double = (weekday == 1 || weekday == 7) ? 0.35 : 0
            let wobble = sin(Double(offset) * 0.9) * 0.18
            let kg = roundKg(trend + weekendBump + wobble)
            samples.append(HealthMetricSample(value: kg, date: morning))
        }
        return samples
    }

    private static func makeBodyFatSeries(_ persona: Persona, now: Date) -> [HealthMetricSample] {
        let cal = Calendar.current
        let start = startingBodyFat(persona)
        let end = currentBodyFat(persona)
        let days = 28
        var samples: [HealthMetricSample] = []
        for offset in 0..<days where offset % 2 == 0 {
            let day = days - 1 - offset
            guard let date = cal.date(byAdding: .day, value: -day, to: now) else { continue }
            let morning = cal.date(bySettingHour: 7, minute: 14, second: 0, of: date) ?? date
            let t = Double(offset) / Double(max(days - 1, 1))
            let base = start + (end - start) * t
            let wobble = sin(Double(offset) * 0.5) * 0.2
            let pct = roundPct(base + wobble)
            samples.append(HealthMetricSample(value: pct, date: morning))
        }
        return samples
    }

    private static func makeDigest(_ persona: Persona, now: Date) -> FitnessDigest {
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "Demo Health digest (DEBUG)"
        digest.generatedAt = now
        digest.stepsToday = persona == .male ? 9_420 : 8_150
        digest.activeEnergyKcalToday = persona == .male ? 640 : 480
        digest.activeEnergyKcalLast7dAverage = persona == .male ? 580 : 430
        digest.appleExerciseMinutesToday = persona == .male ? 42 : 35
        digest.dietaryEnergyKcalToday = persona == .male ? 1_820 : 1_420
        digest.dietaryProteinGramsToday = persona == .male ? 138 : 102
        digest.dietaryFiberGramsToday = persona == .male ? 28 : 26
        digest.dietaryIronMgToday = persona == .male ? 14 : 16
        digest.dietaryPotassiumMgToday = persona == .male ? 3_400 : 3_100
        digest.restingHeartRateBpm = persona == .male ? 58 : 62
        digest.latestHeartRateBpm = persona == .male ? 72 : 76
        digest.heartRateSampleCountToday = 180
        digest.hrvSDNNMs = persona == .male ? 48 : 52
        digest.hrvMedian7dMs = persona == .male ? 45 : 50
        digest.sleepHoursLastNight = 7.2
        digest.averageSleepHours7d = 6.9
        digest.sleepNightsSampled = 7
        digest.oxygenSaturationPercent = 97
        digest.vo2MaxMlKgMin = persona == .male ? 42 : 38
        digest.workoutCountLast24h = 1
        return digest
    }

    private static func makeMeals(_ persona: Persona) -> [MealPlanMeal] {
        switch persona {
        case .male:
            return [
                MealPlanMeal(
                    title: "Egg + oat bowl",
                    timeLabel: "~12:15",
                    ingredients: ["Eggs", "Rolled oats", "Banana", "Peanut butter"],
                    keyMacro: "38g protein",
                    keyMicro: "Potassium + iron",
                    approxKcal: 520
                ),
                MealPlanMeal(
                    title: "Chicken rice box",
                    timeLabel: "~15:30",
                    ingredients: ["Chicken thigh", "Brown rice", "Broccoli", "Chili oil"],
                    keyMacro: "46g protein",
                    keyMicro: "Fiber + iron",
                    approxKcal: 680
                ),
                MealPlanMeal(
                    title: "Salmon + greens",
                    timeLabel: "~19:15",
                    ingredients: ["Salmon", "Pak choi", "Sweet potato"],
                    keyMacro: "42g protein",
                    keyMicro: "Omega-3 + potassium",
                    approxKcal: 610
                ),
            ]
        case .female:
            return [
                MealPlanMeal(
                    title: "Greek yogurt bowl",
                    timeLabel: "~12:00",
                    ingredients: ["Greek yogurt", "Berries", "Pumpkin seeds"],
                    keyMacro: "28g protein",
                    keyMicro: "Calcium + fiber",
                    approxKcal: 380
                ),
                MealPlanMeal(
                    title: "Miso salmon salad",
                    timeLabel: "~15:00",
                    ingredients: ["Salmon", "Mixed greens", "Edamame", "Miso"],
                    keyMacro: "36g protein",
                    keyMicro: "Iron + omega-3",
                    approxKcal: 520
                ),
                MealPlanMeal(
                    title: "Prawn stir-fry",
                    timeLabel: "~19:00",
                    ingredients: ["Prawns", "Veg mix", "Jasmine rice (small)"],
                    keyMacro: "34g protein",
                    keyMicro: "Potassium + iodine",
                    approxKcal: 540
                ),
            ]
        }
    }

    private static func makeChat(_ persona: Persona, now: Date) -> [CoachChatTurn] {
        let name = persona == .male ? "Bob" : "Alice"
        let cal = Calendar.current
        let t0 = cal.date(byAdding: .hour, value: -26, to: now) ?? now
        let t1 = cal.date(byAdding: .hour, value: -25, to: now) ?? now
        let t2 = cal.date(byAdding: .hour, value: -2, to: now) ?? now
        let t3 = cal.date(byAdding: .hour, value: -1, to: now) ?? now
        return [
            CoachChatTurn(
                kind: .user,
                text: "Be honest - am I actually losing or is the scale trolling me?",
                createdAt: t0
            ),
            CoachChatTurn(
                kind: .assistant,
                agent: .orchestrator,
                text: persona == .male
                    ? "\(name), the week trend is down. Weekend salt bumps are noise. Keep the Monday weigh, hit protein, stop inventing a new plan every Tuesday."
                    : "\(name), two-week slope is down. One high morning is not a relapse. Weigh, eat the plan, ignore the panic edit.",
                usedNetwork: true,
                createdAt: t1
            ),
            CoachChatTurn(
                kind: .user,
                text: "What should I push today?",
                createdAt: t2
            ),
            CoachChatTurn(
                kind: .assistant,
                agent: .orchestrator,
                text: persona == .male
                    ? "Protein first, 8k+ steps, no second dinner. If you train, keep it boring and hard - not a hero WOD."
                    : "Hit protein, walk after lunch, leave alcohol alone tonight. That is the whole job.",
                usedNetwork: true,
                createdAt: t3
            ),
        ]
    }

    private static func makeMemory(_ persona: Persona, now: Date) -> [CoachMemoryFact] {
        switch persona {
        case .male:
            return [
                CoachMemoryFact(text: "Lifts Mon/Wed/Fri evenings", createdAt: now, tags: ["training"]),
                CoachMemoryFact(text: "Late espresso habit after 4pm", createdAt: now, tags: ["lifestyle"]),
                CoachMemoryFact(text: "Shellfish allergy", createdAt: now, tags: ["diet"]),
            ]
        case .female:
            return [
                CoachMemoryFact(text: "Runs Tue/Thu", createdAt: now, tags: ["training"]),
                CoachMemoryFact(text: "Peanut allergy", createdAt: now, tags: ["diet"]),
                CoachMemoryFact(text: "Hates crash diets", createdAt: now, tags: ["lifestyle"]),
            ]
        }
    }

    private static func makeMondayCard(
        _ persona: Persona,
        now: Date,
        currentKg: Double,
        weekStartKg: Double
    ) -> MondayCardPayload {
        let week = MondayWeekKey.current(now: now)
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: MondayCardEngine.startOfWeekMonday(now: now))
            ?? now
        let name = persona == .male ? "Bob" : "Alice"
        return MondayCardPayload(
            weekKey: week.storageKey,
            weighInSignature: "demo-\(persona.rawValue)",
            currentKg: currentKg,
            progress: MondayWeekProgress(
                weightDeltaKg: currentKg - weekStartKg,
                fatDeltaPercent: -0.3,
                priorSundayTargetKg: weekStartKg + 0.2,
                adherenceLine: "On pace if you keep mornings honest.",
                signalLines: [
                    "Sleep held ~7h",
                    "Protein mostly logged",
                    "Weekend bump already fading",
                ],
                summaryLine: String(format: "Week open %.1f → now %.1f kg", weekStartKg, currentKg)
            ),
            sundayGoal: MondaySundayGoal(
                targetKg: roundKg(weekStartKg - 0.5),
                sundayDate: sunday,
                weeklyDeltaKg: -0.5,
                pacingLine: "Aggressive week. No soft Sunday.",
                modeRaw: WeeklyTargetMode.aggressive.rawValue
            ),
            encouragement: "\(name), good Monday. Do not negotiate with Thursday.",
            meals: "Protein forward plates. Skip the victory pastry.",
            diagnostic: "Trend is working. Noise is not a plot. Stay boring.",
            usedNetwork: false,
            generatedAt: now
        )
    }
}

private extension FastingWindow {
    /// Cache helper when IF is nil — MealPlanEngine still wants a token.
    static var noneForCache: FastingWindow {
        FastingWindow(
            eatingWindowStartMinutes: 0,
            eatingWindowEndMinutes: 24 * 60,
            cacheToken: "none@0-1440",
            protocolLabel: "none",
            fastingHours: 0
        )
    }
}

private func roundKg(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

private func roundPct(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}
#endif
