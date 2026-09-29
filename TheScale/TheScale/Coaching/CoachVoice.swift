import Foundation

/// Sex-tuned coach voice for Grok, on-device FM, Metal polish, and deterministic copy.
/// Male: blunt badass humour with numbers. Female: nurturing, praise-heavy, funny coach
/// who leads with visual food / body pictures instead of bare calorie figures.
enum CoachVoice {
    /// Fallback address when the name field is empty.
    static func who(_ name: String, sex: UserBodyProfile.Sex) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch sex {
        case .female: return "lovely"
        case .male: return "Operator"
        }
    }

    /// Shared rules injected into Grok / Foundation Models / Metal polish prompts.
    static func llmRules(sex: UserBodyProfile.Sex) -> String {
        switch sex {
        case .male:
            return """
            Voice: badass, dark humour, sometimes vulgar, always friendly. Call the user by name.
            Keep it punchy. ASCII hyphens only. No em dashes or en dashes.
            Never use AI tells ("As an AI…", "I'd be happy to…", "Certainly!", robotic hedging).
            Do NOT append medical disclaimers. Fitness coaching only. No diagnosis.
            CRITICAL: Never re-ask height, age, sex, name, diet, or targets already in the profile block.
            CRITICAL: Be time-aware. Night = recovery and food timing, not gym PRs.
            CRITICAL: Push back when the ask is unsafe or mismatched to the clock.
            """
        case .female:
            return """
            Voice: warm, nurturing, funny coach who constantly praises effort and presence. Call her by name.
            Celebrate showing up. Soft accountability with wit, never drill-sergeant or shame.
            Write in full, friendly sentences. No military jargon, no acronyms like ETA, no "Operator", no "DRILL".
            Prefer "dream weight", "around [date]", "per week" over shorthand. ASCII hyphens only. No em dashes.
            CRITICAL FOOD PICTURES: Do not lead with bare calorie or gram figures (avoid "1343 kcal", "92 g protein" as the headline).
            Translate energy and protein into real-life visuals she can see: palm of chicken or tofu, fist of rice, cupped handful of berries, big handful of kale, two eggs in the pan, a yogurt cup.
            Example: "about three palm-size protein plates with a big handful of greens each" instead of "1343 kcal".
            If a number must appear, tuck it after the picture in parentheses.
            Never use AI tells ("As an AI…", "I'd be happy to…", "Certainly!", robotic hedging).
            Do NOT append medical disclaimers. Fitness coaching only. No diagnosis.
            CRITICAL: Never re-ask height, age, sex, name, diet, or targets already in the profile block.
            CRITICAL: Be time-aware. Night = recovery, comfort food timing, rest. Not a late-night gym order.
            CRITICAL: Redirect unsafe asks gently and protectively. Keep the vibe upbeat and kind.
            """
        }
    }

    /// Compact banner / notification voice (Watch glance + iPhone body).
    static func bannerRules(sex: UserBodyProfile.Sex) -> String {
        switch sex {
        case .male:
            return """
            You write for fatnag. Notifications mirror to Apple Watch and iPhone.
            TITLE is Watch glance: max 22 chars, verb or number first, emoji OK (including 💩 on morning weigh). NO name prefix.
            BODY is iPhone expanded: call the user by name when natural. Friendly, badass, dark humour; sometimes vulgar; never corporate. Emoji OK.
            Never use em dashes or en dashes. Use ASCII hyphen or a period.
            Never say you are an AI, language model, or Apple Intelligence.
            Never add medical disclaimers, diagnoses, or consult-a-doctor lines.
            """
        case .female:
            return """
            You write for fatnag. Notifications mirror to Apple Watch and iPhone.
            TITLE is Watch glance: max 22 chars, verb or number first, emoji OK. NO name prefix.
            BODY is iPhone expanded: call her by name when natural. Warm, nurturing, funny coach who praises effort. Emoji OK.
            Soft accountability with humour. Never drill-sergeant, never shame, never short-form jargon (no ETA, no Operator, no DRILL).
            Prefer visual food pictures (palm of protein, handful of greens) over bare calorie numbers.
            Prefer full friendly sentences. Never use em dashes or en dashes. Use ASCII hyphen or a period.
            Never say you are an AI, language model, or Apple Intelligence.
            Never add medical disclaimers, diagnoses, or consult-a-doctor lines.
            """
        }
    }

    // MARK: - Visual portion pictures (female-first coaching)

    /// Daily energy budget as a plate picture. Male keeps the number; female leads with visuals.
    static func energyBudgetPhrase(
        kcal: Int,
        diet: DietPreference,
        sex: UserBodyProfile.Sex
    ) -> String {
        switch sex {
        case .male:
            return "under \(kcal) kcal"
        case .female:
            return energyBudgetPicture(kcal: kcal, diet: diet)
        }
    }

    /// Chip / short label for home energy target.
    static func energyChipLine(
        kcal: Int,
        diet: DietPreference,
        sex: UserBodyProfile.Sex
    ) -> String {
        switch sex {
        case .male:
            return "\(kcal) kcal max"
        case .female:
            let plates = plateCount(forKcal: kcal)
            return "~\(plates) cozy plates"
        }
    }

    static func proteinPhrase(
        grams: Int,
        diet: DietPreference,
        sex: UserBodyProfile.Sex
    ) -> String {
        switch sex {
        case .male:
            return "\(grams) g protein"
        case .female:
            return proteinPicture(grams: grams, diet: diet)
        }
    }

    static func proteinChipLine(
        grams: Int,
        diet: DietPreference,
        sex: UserBodyProfile.Sex
    ) -> String {
        switch sex {
        case .male:
            return "\(grams) g"
        case .female:
            let palms = palmCount(forProteinGrams: grams)
            return "~\(palms) protein palms"
        }
    }

    /// Full-sentence daily energy picture for advice lines.
    static func energyBudgetPicture(kcal: Int, diet: DietPreference) -> String {
        let plates = plateCount(forKcal: kcal)
        let protein = proteinNoun(diet: diet)
        let greens = greensNoun(diet: diet)
        let carb = carbNoun(diet: diet)
        let snack = snackNoun(diet: diet)
        if plates <= 2 {
            return "about \(plates) palm-of-\(protein) plates with a fist of \(carb) and a big handful of \(greens), plus \(snack) if you get snacky"
        }
        return "about \(plates) palm-of-\(protein) plates across the day, each with a fist of \(carb) and a big handful of \(greens), plus \(snack) tucked in"
    }

    static func proteinPicture(grams: Int, diet: DietPreference) -> String {
        let palms = palmCount(forProteinGrams: grams)
        let protein = proteinNoun(diet: diet)
        return "about \(palms) palm-size servings of \(protein)"
    }

    static func plateCount(forKcal kcal: Int) -> Int {
        max(2, min(4, Int((Double(max(800, kcal)) / 450.0).rounded())))
    }

    static func palmCount(forProteinGrams grams: Int) -> Int {
        max(2, min(6, Int((Double(max(40, grams)) / 25.0).rounded())))
    }

    private static func proteinNoun(diet: DietPreference) -> String {
        switch diet {
        case .vegan: return "tofu, tempeh, or chickpeas"
        case .vegetarian: return "eggs, yogurt, or legumes"
        case .pescatarian: return "fish or eggs"
        case .omnivore, .other: return "chicken, fish, or tofu"
        }
    }

    private static func greensNoun(diet: DietPreference) -> String {
        switch diet {
        case .vegan, .vegetarian: return "kale or mixed greens"
        default: return "salad greens or broccoli"
        }
    }

    private static func carbNoun(diet: DietPreference) -> String {
        switch diet {
        case .vegan: return "rice, potatoes, or oats"
        default: return "rice or potatoes"
        }
    }

    private static func snackNoun(diet: DietPreference) -> String {
        switch diet {
        case .vegan: return "a cupped handful of berries or a small apple"
        case .vegetarian: return "a yogurt cup or a cupped handful of berries"
        default: return "a cupped handful of berries or a cheese stick"
        }
    }

    // MARK: - Hero chrome

    static func badge(for tone: WeighInCoachTone, sex: UserBodyProfile.Sex) -> String {
        switch (sex, tone) {
        case (.female, .sergeant): return "SOFT NUDGE"
        case (.female, .encourage): return "GLOW"
        case (.female, .skeptical): return "CURIOUS"
        case (.male, .sergeant): return "DRILL"
        case (.male, .encourage): return "HERO"
        case (.male, .skeptical): return "SIDE-EYE"
        }
    }

    static func cta(for tone: WeighInCoachTone, sex: UserBodyProfile.Sex) -> String {
        switch (sex, tone) {
        case (.female, .sergeant): return "I've got dinner"
        case (.female, .encourage): return "Keep glowing"
        case (.female, .skeptical): return "See you tomorrow"
        case (.male, .sergeant): return "I'll fix dinner"
        case (.male, .encourage): return "Keep the streak"
        case (.male, .skeptical): return "Noted. Next."
        }
    }

    // MARK: - Pace / dream-weight lines

    static func onPlanLine(
        remainingAbsKg: Double,
        paceKgPerWeek: Double,
        planText: String,
        sex: UserBodyProfile.Sex,
        unitSystem: PreferredUnitSystem
    ) -> String {
        let remain = UnitFormat.massString(remainingAbsKg, system: unitSystem, fractionDigits: 1)
        let pace = UnitFormat.massDeltaString(paceKgPerWeek, system: unitSystem, fractionDigits: 2)
        switch sex {
        case .female:
            return "Your plan lands \(planText). About \(pace) per week, \(remain) still to go."
        case .male:
            return "On plan for \(planText) at \(pace)/wk · \(remain) to go."
        }
    }

    static func unrealisticDateLine(
        remainingAbsKg: Double,
        planText: String,
        proposedText: String,
        sex: UserBodyProfile.Sex,
        unitSystem: PreferredUnitSystem
    ) -> String {
        let remain = UnitFormat.massString(remainingAbsKg, system: unitSystem, fractionDigits: 1)
        switch sex {
        case .female:
            return "\(planText) asks for more than a safe cut on \(remain). Commando meals are on. Earliest honest date: \(proposedText)."
        case .male:
            return "\(planText) is too fast for \(remain). Commando intake is on. Earliest honest date: \(proposedText)."
        }
    }

    static func paceLine(
        remainingAbsKg: Double,
        paceKgPerWeek: Double,
        etaText: String,
        plannedBit: String,
        sex: UserBodyProfile.Sex,
        unitSystem: PreferredUnitSystem
    ) -> String {
        let remain = UnitFormat.massString(remainingAbsKg, system: unitSystem, fractionDigits: 1)
        let pace = UnitFormat.massDeltaString(paceKgPerWeek, system: unitSystem, fractionDigits: 2)
        switch sex {
        case .female:
            return "At this pace you could land near \(etaText) (about \(pace) per week). \(remain) still to go.\(plannedBit)"
        case .male:
            return "ETA \(etaText) at \(pace)/wk · \(remain) to go.\(plannedBit)"
        }
    }

    static func flatPaceLine(
        remainingAbsKg: Double,
        plannedBit: String,
        sex: UserBodyProfile.Sex,
        unitSystem: PreferredUnitSystem
    ) -> String {
        let remain = UnitFormat.massString(remainingAbsKg, system: unitSystem, fractionDigits: 1)
        switch sex {
        case .female:
            return "\(remain) to your dream weight. Pace is soft right now.\(plannedBit) Proud you stepped on."
        case .male:
            return "\(remain) to goal. Pace too flat to date.\(plannedBit)"
        }
    }

    static func wrongWayPaceLine(
        remainingAbsKg: Double,
        paceKgPerWeek: Double,
        sex: UserBodyProfile.Sex,
        unitSystem: PreferredUnitSystem
    ) -> String {
        let remain = UnitFormat.massString(remainingAbsKg, system: unitSystem, fractionDigits: 1)
        let pace = UnitFormat.massDeltaString(paceKgPerWeek, system: unitSystem, fractionDigits: 2)
        switch sex {
        case .female:
            return "\(remain) to your dream weight, and this week's pace wandered the other way (\(pace) per week). Still glad you showed up."
        case .male:
            return "\(remain) to goal, but current pace (\(pace)/wk) goes the wrong way."
        }
    }

    static func atGoalLine(sex: UserBodyProfile.Sex) -> String {
        switch sex {
        case .female: return "You're right on your dream weight. Soak that in."
        case .male: return "You're at goal weight. Hold the line."
        }
    }

    static func emptyPaceLine(sex: UserBodyProfile.Sex) -> String {
        switch sex {
        case .female: return "Weigh in a few times and I'll sketch when you might land on your dream weight."
        case .male: return "Weigh in a few times to project ETA to your goal weight."
        }
    }
}
