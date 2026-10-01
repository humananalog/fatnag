import Foundation
import FoundationModels
import ScaleOnDevicePolish

// MARK: - Structured outputs

@Generable(description: "Local notification glance title (Watch) and expanded body (iPhone) for fatnag")
struct NotificationCopyDraft: Equatable, Sendable {
    @Guide(description: "Watch glance title. Max 22 characters. Verb or number first. Emoji OK (💩 on weigh drills). NO name prefix. No em dashes. No AI markers.")
    var title: String

    @Guide(description: "iPhone expanded body. Friendly badass dark humour. Call user by name when natural. Max ~120 characters. No em dashes. No medical disclaimer. No AI markers.")
    var body: String
}

@Generable(description: "Whether a local notification is worth firing right now")
struct PingJudgment: Equatable, Sendable {
    @Guide(description: "True only if the ping is necessary: bad trend, Watch not worn, or pre-sleep HR missing/elevated. False for noise.")
    var shouldNotify: Bool

    @Guide(description: "One short plain reason for the decision.")
    var reason: String
}

@Generable(description: "Compact on-device memory facts extracted from user chat")
struct MemoryExtractionDraft: Equatable, Sendable {
    @Guide(description: "Zero to three durable facts worth remembering (diet, training, lifestyle). Empty if nothing sticky.")
    var facts: [String]
}

@Generable(description: "One meal with metric ingredient portions for an on-device menu")
struct MealPlanFMMealDraft: Equatable, Sendable {
    @Guide(description: "Meal title by slot. With IF use Lunch/Dinner or First plate/Mid plate/Last plate. Never Breakfast when fasting.")
    var title: String

    @Guide(description: "Local time label like ~12:30.")
    var time: String

    @Guide(description: "2-5 ingredients with metric portions (g or ml), e.g. Chicken breast 140 g.")
    var ingredients: [String]

    @Guide(description: "Key macro line, e.g. Protein 35 g.")
    var macro: String

    @Guide(description: "Key micro line, e.g. Iron ~3 mg.")
    var micro: String

    @Guide(description: "Approximate kcal for this meal.")
    var kcal: Int
}

@Generable(description: "Next meals for the day with metric portions")
struct MealPlanFMDraft: Equatable, Sendable {
    @Guide(description: "Upcoming meals for the eating window. Match the requested plate count (often 2 for 16-8).")
    var meals: [MealPlanFMMealDraft]
}

@Generable(description: "Onboarding profile fields inferred on-device from a freeform note")
struct OnboardingProfileFMDraft: Equatable, Sendable {
    @Guide(description: "Diet preference: omnivore, pescatarian, vegetarian, vegan, other, or empty if unknown.")
    var diet: String

    @Guide(description: "City or region only, or empty if unknown.")
    var location: String

    @Guide(description: "Short ethnicity or culture label, or empty.")
    var ethnicity: String

    @Guide(description: "Preferred language name, or empty.")
    var preferredLanguage: String

    @Guide(description: "One short coach-facing vibe line (max ~120 chars), or empty.")
    var culturalVibe: String

    @Guide(description: "Ideal weight in kg if stated, otherwise 0.")
    var idealWeightKg: Double

    @Guide(description: "Ideal body fat percent if stated, otherwise 0.")
    var idealBodyFatPercent: Double
}

// MARK: - Coach

/// On-device Foundation Models helpers. Privacy-first; never sends Health off-device.
/// Graceful no-op / algorithmic fallback when Apple Intelligence is off or ineligible.
enum FoundationModelCoach {
    // MARK: Notifications

    /// True when the UI is foreground-active. HealthKit observer wakes often resume the
    /// process before `.active`; skip Metal sidecar polish there (template copy is enough).
    /// Uses `AppSceneActivity` — never `UIApplication.applicationState` (Main Thread Checker).
    private static var prefersSidecarMetal: Bool {
        AppSceneActivity.isActive
    }

    /// Refine algorithmic notification title/body. Returns fallbacks unchanged if FM + sidecar unavailable.
    static func refineNotificationCopy(
        profileName: String,
        kind: String,
        fallbackTitle: String,
        fallbackBody: String,
        context: String,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = ""
    ) async -> (title: String, body: String, usedFoundationModel: Bool) {
        let voice = AppLanguageStore.locked(
            CoachVoice.bannerRules(sex: sex, ageYears: ageYears)
                + cultureSuffix(cultureContext)
        )
        guard FoundationModelAvailability.isAvailable else {
            guard prefersSidecarMetal else {
                return (fallbackTitle, fallbackBody, false)
            }
            let sidecar = await OnDevicePolishService.shared.refineNotificationCopy(
                profileName: profileName,
                kind: kind,
                fallbackTitle: fallbackTitle,
                fallbackBody: fallbackBody,
                context: context,
                voiceRules: voice
            )
            return (sidecar.title, sidecar.body, sidecar.usedSidecar)
        }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voice)
            let prompt = """
                Draft a local notification for \(name).
                Kind: \(kind)
                Context: \(context)
                Fallback title: \(fallbackTitle)
                Fallback body: \(fallbackBody)
                Prefer a sharper rewrite of the fallback; keep the same facts.
                """
            var options = GenerationOptions()
            options.temperature = 0.7
            options.maximumResponseTokens = 120
            let response = try await session.respond(
                to: prompt,
                generating: NotificationCopyDraft.self,
                options: options
            )
            let draft = response.content
            let title = CoachCopySanitize.clean(draft.title)
            let body = CoachCopySanitize.clean(draft.body)
            let safeTitle = title.isEmpty
                ? fallbackTitle
                : ScaleNotificationCopy.glanceSanitize(title, max: 22)
            let safeBody = body.isEmpty ? fallbackBody : clamp(body, max: 140)
            return (safeTitle, safeBody, true)
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            guard prefersSidecarMetal else {
                return (fallbackTitle, fallbackBody, false)
            }
            let sidecar = await OnDevicePolishService.shared.refineNotificationCopy(
                profileName: profileName,
                kind: kind,
                fallbackTitle: fallbackTitle,
                fallbackBody: fallbackBody,
                context: context,
                voiceRules: voice
            )
            return (sidecar.title, sidecar.body, sidecar.usedSidecar)
        }
    }

    /// FM / sidecar judgment on top of algorithmic triggers. Defaults to allow when both are off.
    static func shouldSendPing(
        profileName: String,
        kind: String,
        algorithmicReason: String,
        extraContext: String = "",
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = ""
    ) async -> (shouldNotify: Bool, reason: String, usedFoundationModel: Bool) {
        let voice = AppLanguageStore.locked(
            CoachVoice.bannerRules(sex: sex, ageYears: ageYears)
                + cultureSuffix(cultureContext)
        )
        guard FoundationModelAvailability.isAvailable else {
            guard prefersSidecarMetal else {
                return (true, "Background wake; algorithmic trigger stands.", false)
            }
            let sidecar = await OnDevicePolishService.shared.shouldSendPing(
                profileName: profileName,
                kind: kind,
                algorithmicReason: algorithmicReason,
                extraContext: extraContext,
                voiceRules: voice
            )
            return (sidecar.shouldNotify, sidecar.reason, sidecar.usedSidecar)
        }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voice)
            let prompt = """
                Decide if \(name) should get a local notification now.
                Kind: \(kind)
                Algorithmic reason: \(algorithmicReason)
                Extra: \(extraContext.isEmpty ? "none" : extraContext)
                Rules: allow necessary bad-trend, Watch-wear, and pre-sleep HR missing/elevated pings.
                Suppress only if the signal is clearly noise, duplicate-feeling, or too mild to bother someone.
                When unsure, allow the ping (shouldNotify = true).
                """
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = 80
            let response = try await session.respond(
                to: prompt,
                generating: PingJudgment.self,
                options: options
            )
            let judgment = response.content
            return (
                judgment.shouldNotify,
                CoachCopySanitize.clean(judgment.reason),
                true
            )
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            guard prefersSidecarMetal else {
                return (true, "FM judgment failed; algorithmic trigger stands.", false)
            }
            let sidecar = await OnDevicePolishService.shared.shouldSendPing(
                profileName: profileName,
                kind: kind,
                algorithmicReason: algorithmicReason,
                extraContext: extraContext,
                voiceRules: voice
            )
            if sidecar.usedSidecar {
                return (sidecar.shouldNotify, sidecar.reason, true)
            }
            return (true, "FM judgment failed; algorithmic trigger stands.", false)
        }
    }

    // MARK: Digest / offline assist

    /// Short on-device summary of a Health digest before (or without) Grok.
    static func summarizeFitnessDigest(
        profileName: String,
        digestBlock: String,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = ""
    ) async -> String? {
        let voice = AppLanguageStore.locked(
            CoachVoice.bannerRules(sex: sex, ageYears: ageYears)
                + cultureSuffix(cultureContext)
        )
        guard FoundationModelAvailability.isAvailable else {
            guard prefersSidecarMetal else { return nil }
            return await OnDevicePolishService.shared.summarizeFitnessDigest(
                profileName: profileName,
                digestBlock: digestBlock,
                voiceRules: voice
            )
        }
        guard !digestBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voice)
            let prompt = """
                \(name) asked for a quick private read of this Apple Health digest.
                Stay on-device. Under 90 words. One next action that fits the time of day if obvious.
                Digest:
                \(digestBlock)
                """
            var options = GenerationOptions()
            options.temperature = 0.6
            options.maximumResponseTokens = 180
            let response = try await session.respond(to: prompt, options: options)
            let text = CoachCopySanitize.clean(response.content)
            return text.isEmpty ? nil : text
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            return await OnDevicePolishService.shared.summarizeFitnessDigest(
                profileName: profileName,
                digestBlock: digestBlock,
                voiceRules: voice
            )
        }
    }

    /// Optional FM / sidecar pass to pull sticky facts; merges with heuristic extractor upstream.
    static func extractMemoryFacts(
        from userText: String,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30
    ) async -> [CoachMemoryFact] {
        let voice = AppLanguageStore.locked(CoachVoice.bannerRules(sex: sex, ageYears: ageYears))
        guard FoundationModelAvailability.isAvailable else {
            return await OnDevicePolishService.shared.extractMemoryFacts(
                from: userText,
                voiceRules: voice
            ).compactMap { raw in
                let clean = CoachCopySanitize.clean(raw)
                guard clean.count >= 6 else { return nil }
                return CoachMemoryFact(text: clean, tags: ["sidecar", "lifestyle"])
            }
        }
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return [] }
        do {
            let session = LanguageModelSession(instructions: voice)
            let prompt = """
                Extract durable personal facts worth remembering for a fitness coach.
                Only keep diet, training, lifestyle constraints the user stated about themselves.
                Skip one-off questions and reminder scheduling.
                User said: \(trimmed)
                """
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = 120
            let response = try await session.respond(
                to: prompt,
                generating: MemoryExtractionDraft.self,
                options: options
            )
            return response.content.facts.compactMap { raw in
                let clean = CoachCopySanitize.clean(raw)
                guard clean.count >= 6 else { return nil }
                return CoachMemoryFact(text: clean, tags: ["fm", "lifestyle"])
            }
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            return await OnDevicePolishService.shared.extractMemoryFacts(
                from: userText,
                voiceRules: voice
            ).compactMap { raw in
                let clean = CoachCopySanitize.clean(raw)
                guard clean.count >= 6 else { return nil }
                return CoachMemoryFact(text: clean, tags: ["sidecar", "lifestyle"])
            }
        }
    }

    // MARK: Meal plan (quota / offline)

    /// On-device meal menu when weekly Grok credits are exhausted. Metric portions required.
    /// Returns nil when FM is unavailable or output is too thin (caller uses templated menu).
    static func generateMealPlan(
        name: String,
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int,
        microHint: String,
        weeklyDeltaKg: Double,
        fasting: FastingWindow,
        memoryBlock: String,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = "",
        now: Date = Date()
    ) async -> [MealPlanMeal]? {
        guard FoundationModelAvailability.isAvailable else { return nil }
        let who = CoachVoice.who(name, sex: sex)
        let localTime = now.formatted(date: .omitted, time: .shortened)
        let fastingLine: String = {
            if fasting.isActive {
                let open = MealPlanEngine.formatHour(fasting.eatingStartHour)
                let close = MealPlanEngine.formatHour(fasting.eatingEndHour)
                return "Intermittent fasting \(fasting.cacheToken). Eating window \(open)-\(close). Do not place meals outside the window. Never title a meal Breakfast. For 2 plates use Lunch then Dinner."
            }
            return "No fasting window."
        }()
        let mem = memoryBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let plateCount = MealPlanEngine.preferredMealCount(for: fasting)
        let slotHint = MealPlanEngine.slotTitles(count: plateCount, fasting: fasting).joined(separator: ", ")
        let picture = CoachVoice.energyBudgetPicture(kcal: maxKcal, diet: diet)
        let proteinPic = CoachVoice.proteinPicture(grams: proteinGrams, diet: diet)
        let femaleHint = sex == .female
            ? "Also describe portions with palms/fists/handfuls in titles or micro lines when natural. Daily picture: \(picture). Protein picture: \(proteinPic)."
            : ""
        do {
            let session = LanguageModelSession(instructions: AppLanguageStore.locked("""
                You write practical meal menus for FATNAG on-device.
                \(CoachVoice.bannerRules(sex: sex, ageYears: ageYears))
                \(CoachVoice.ageVoiceRules(ageYears: ageYears))
                \(cultureSuffix(cultureContext))
                Fitness coaching only. Never diagnose. No em dashes.
                Every ingredient needs a metric portion (g or ml). Real dishes, not fluff.
                Honour diet preference and fasting windows. Prefer local staples when culture context is set.
                Meal titles and micro lines must be in the LANGUAGE reply language.
                """))
            let prompt = """
                Build exactly \(plateCount) upcoming meal\(plateCount == 1 ? "" : "s") for \(who) from local now \(localTime).
                Diet: \(diet.title). Daily max \(maxKcal) kcal. Protein \(proteinGrams) g. Micro focus: \(microHint).
                Weekly weight nudge \(String(format: "%+.1f", weeklyDeltaKg)) kg (keep a mild deficit if negative).
                \(femaleHint)
                \(fastingLine)
                Slot titles in order: \(slotHint).
                \(mem.isEmpty ? "" : "Memory:\n\(mem)")
                Ingredients must include metric grams or millilitres. Do not invent extra snacks.
                """
            var options = GenerationOptions()
            options.temperature = 0.5
            options.maximumResponseTokens = 420
            let response = try await session.respond(
                to: prompt,
                generating: MealPlanFMDraft.self,
                options: options
            )
            let drafts = response.content.meals
            var meals: [MealPlanMeal] = []
            for draft in drafts.prefix(plateCount) {
                let ingredients = draft.ingredients
                    .map { CoachCopySanitize.clean($0) }
                    .filter { !$0.isEmpty }
                guard ingredients.count >= 2 else { continue }
                let hasMetric = ingredients.contains {
                    $0.range(of: #"\d+\s*(g|ml)\b"#, options: .regularExpression) != nil
                }
                guard hasMetric else { continue }
                let title = CoachCopySanitize.clean(draft.title)
                let time = CoachCopySanitize.clean(draft.time)
                let macro = CoachCopySanitize.clean(draft.macro)
                let micro = CoachCopySanitize.clean(draft.micro)
                meals.append(
                    MealPlanMeal(
                        title: title.isEmpty ? "Meal" : title,
                        timeLabel: time,
                        ingredients: Array(ingredients.prefix(5)),
                        keyMacro: macro.isEmpty ? "Protein" : macro,
                        keyMicro: micro.isEmpty ? "Fiber" : micro,
                        approxKcal: max(80, min(1200, draft.kcal))
                    )
                )
            }
            return meals.count >= plateCount ? meals : nil
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            return nil
        }
    }

    // MARK: Onboarding

    /// On-device profile fill for first-run. Never leaves the phone. Falls back to heuristics when FM is off.
    static func inferOnboardingProfile(
        name: String,
        freeform: String,
        heightCm: Double,
        ageYears: Double,
        sex: UserBodyProfile.Sex,
        idealKg: Double,
        allowOnDeviceModel: Bool = true
    ) async -> OnboardingInferenceDraft {
        let local = OnboardingLocalInference.infer(from: freeform, name: name)
        guard allowOnDeviceModel else { return local }
        guard FoundationModelAvailability.isAvailable else {
            // Sidecar can refine vibe later when ready; keep deterministic local merge for first paint.
            return local
        }
        let trimmed = freeform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return local }

        do {
            let session = LanguageModelSession(instructions: AppLanguageStore.locked("""
                You structure onboarding profiles for FATNAG, a private fitness app.
                Stay on-device. Infer only what the user's note supports. Prefer empty / 0 over guessing.
                Never invent height, age, or sex. Never add medical advice.
                """))
            let prompt = """
                Extract profile fields from this freeform note for \(name.isEmpty ? "the user" : name).
                Known body (do not invent; may use when interpreting goals): height \(Int(heightCm.rounded())) cm, age \(Int(ageYears.rounded())), sex \(sex.rawValue), stated ideal \(String(format: "%.1f", idealKg)) kg.
                Freeform note:
                \(trimmed)
                """
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = 220
            let response = try await session.respond(
                to: prompt,
                generating: OnboardingProfileFMDraft.self,
                options: options
            )
            let remote = draft(from: response.content)
            return OnboardingLocalInference.merge(local: local, remote: remote)
        } catch {
            FoundationModelAvailability.noteRuntimeFailure(error)
            return local
        }
    }

    static func draft(from fm: OnboardingProfileFMDraft) -> OnboardingInferenceDraft {
        let dietRaw = fm.diet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let diet = DietPreference(rawValue: dietRaw)
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.lowercased() == "empty" || t.lowercased() == "unknown" || t.lowercased() == "null" {
                return nil
            }
            return t
        }
        var idealW: Double? = fm.idealWeightKg
        if let w = idealW, w < 35 || w > 250 { idealW = nil }
        if idealW == 0 { idealW = nil }
        var idealBF: Double? = fm.idealBodyFatPercent
        if let bf = idealBF, bf < 4 || bf > 45 { idealBF = nil }
        if idealBF == 0 { idealBF = nil }

        return OnboardingInferenceDraft(
            diet: diet,
            location: clean(fm.location),
            ethnicity: clean(fm.ethnicity),
            preferredLanguage: clean(fm.preferredLanguage),
            culturalVibe: clean(fm.culturalVibe),
            idealWeightKg: idealW,
            idealBodyFatPercent: idealBF,
            intermittentFasting: nil,
            usedNetwork: false,
            sourceLabel: "foundation-model"
        )
    }

    // MARK: Helpers

    private static func cultureSuffix(_ cultureContext: String) -> String {
        let trimmed = cultureContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\nCulture / origin cues (use for jokes and food examples; never stereotype):\n\(trimmed)\n"
    }

    private static func clamp(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let idx = text.index(text.startIndex, offsetBy: max - 1)
        return String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
