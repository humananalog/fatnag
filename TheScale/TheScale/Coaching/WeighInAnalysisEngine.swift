import Foundation

/// Post-weigh hero moment voice. Humour first. Never a diagnosis.
enum WeighInCoachTone: String, Equatable, Sendable {
    /// Firm accountability kick (male: drill; female: soft nudge).
    case sergeant
    /// Warm push. For real progress.
    case encourage
    /// Curious / dry side-eye. For flat / baseline moments.
    case skeptical

    func badge(sex: UserBodyProfile.Sex) -> String {
        CoachVoice.badge(for: self, sex: sex)
    }

    func cta(sex: UserBodyProfile.Sex) -> String {
        CoachVoice.cta(for: self, sex: sex)
    }
}

struct WeighInAnalysisCard: Equatable, Sendable {
    var tone: WeighInCoachTone
    var headline: String
    var body: String
    var deltaKg: Double?
    var weighedKg: Double
    var createdAt: Date
    /// Short pop-culture tagline under the body (may be empty).
    var popLine: String
    /// Voice chrome for hero badges / CTAs.
    var sex: UserBodyProfile.Sex

    /// Negative day/week delta → winner energy (minus sign pays off the morning drill).
    var isWinnerLoss: Bool {
        guard let deltaKg else { return false }
        return deltaKg < -0.001
    }

    /// Signed mass delta for UI (`-650g`, `-1.20 kg`). Nil when no prior baseline.
    func deltaDisplay(system: PreferredUnitSystem) -> String? {
        guard let deltaKg else { return nil }
        return UnitFormat.massDeltaString(deltaKg, system: system)
    }
}

enum WeighInAnalysisEngine {
    /// Build a hero moment from this weigh-in vs last Health baseline + profile vibe.
    static func build(
        name: String,
        weighedKg: Double,
        previousKg: Double?,
        weeklyGoal: WeeklyMiniGoal,
        idealKg: Double,
        profile: UserBodyProfile? = nil,
        chartCommentsBlock: String = "",
        unitSystem: PreferredUnitSystem = .metric,
        now: Date = Date()
    ) -> WeighInAnalysisCard {
        let sex = profile?.sex ?? .male
        let who = CoachVoice.who(name, sex: sex)
        let delta: Double? = previousKg.map { weighedKg - $0 }
        let towardIdeal = weighedKg - idealKg
        let cutting = weeklyGoal.targetDeltaKg < -0.05
        let seed = deterministicSeed(
            name: who,
            weighedKg: weighedKg,
            dayKey: dayKey(now: now)
        )
        let vibe = PopCultureLens.from(profile: profile)

        let tone: WeighInCoachTone
        let headline: String
        let body: String
        let pop: String

        if let delta {
            if cutting {
                if delta <= -0.15 {
                    tone = .encourage
                    let pack = encouragePack(
                        who: who,
                        delta: delta,
                        towardIdeal: towardIdeal,
                        vibe: vibe,
                        seed: seed,
                        unitSystem: unitSystem,
                        sex: sex
                    )
                    headline = pack.headline
                    body = pack.body
                    pop = pack.pop
                } else if delta <= 0.12 {
                    tone = .skeptical
                    let pack = skepticalPack(
                        who: who,
                        delta: delta,
                        vibe: vibe,
                        seed: seed,
                        unitSystem: unitSystem,
                        sex: sex
                    )
                    headline = pack.headline
                    body = pack.body
                    pop = pack.pop
                } else {
                    tone = .sergeant
                    let pack = sergeantPack(
                        who: who,
                        delta: delta,
                        vibe: vibe,
                        seed: seed,
                        unitSystem: unitSystem,
                        sex: sex
                    )
                    headline = pack.headline
                    body = pack.body
                    pop = pack.pop
                }
            } else if abs(delta) <= 0.15 {
                tone = .skeptical
                let pack = skepticalPack(
                    who: who,
                    delta: delta,
                    vibe: vibe,
                    seed: seed,
                    unitSystem: unitSystem,
                    sex: sex
                )
                headline = pack.headline
                body = pack.body
                pop = pack.pop
            } else if delta > 0.15 {
                tone = .encourage
                let pack = encouragePack(
                    who: who,
                    delta: delta,
                    towardIdeal: towardIdeal,
                    vibe: vibe,
                    seed: seed,
                    gaining: true,
                    unitSystem: unitSystem,
                    sex: sex
                )
                headline = pack.headline
                body = pack.body
                pop = pack.pop
            } else {
                tone = .sergeant
                let pack = sergeantPack(
                    who: who,
                    delta: delta,
                    vibe: vibe,
                    seed: seed,
                    unitSystem: unitSystem,
                    sex: sex
                )
                headline = pack.headline
                body = pack.body
                pop = pack.pop
            }
        } else {
            tone = .skeptical
            let mass = UnitFormat.massString(weighedKg, system: unitSystem, fractionDigits: 1)
            switch sex {
            case .female:
                headline = "Baseline locked in, \(who)."
                body = "\(mass) on the board. Next weigh-in gets the parade, the tease, or the soft nudge. Proud you started."
            case .male:
                headline = "Baseline locked, \(who)."
                body = "\(mass) on the board. Next weigh-in gets the parade, the roast, or the drill."
            }
            pop = vibe.baselinePop(seed: seed)
        }

        _ = chartCommentsBlock
        return WeighInAnalysisCard(
            tone: tone,
            headline: CoachCopySanitize.clean(headline),
            body: CoachCopySanitize.clean(body),
            deltaKg: delta,
            weighedKg: weighedKg,
            createdAt: now,
            popLine: CoachCopySanitize.clean(pop),
            sex: sex
        )
    }

    // MARK: - Tone packs

    private static func sergeantPack(
        who: String,
        delta: Double,
        vibe: PopCultureLens,
        seed: Int,
        unitSystem: PreferredUnitSystem,
        sex: UserBodyProfile.Sex
    ) -> (headline: String, body: String, pop: String) {
        let signed = UnitFormat.massDeltaString(delta, system: unitSystem)
        switch sex {
        case .female:
            let headlines = [
                "Gentle course-correct, \(who).",
                "Tiny detour. Still your plot.",
                "Kitchen reset with kindness.",
                "Not doom. Just dinner."
            ]
            let bodies = [
                "\(signed) since last. You're still showing up. Keep dinner to a palm of protein and a big handful of greens.",
                "\(signed). Close the kitchen with a smile. Protein first, then rest. Proud of you for looking.",
                "\(signed) wandered on. March it back with boring food and an early close. You've got this."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 3),
                vibe.sergeantPop(seed: seed)
            )
        case .male:
            let headlines = [
                "Drop and give me zero snacks, \(who).",
                "ATTENTION. The scale filed a complaint.",
                "Wrong way, recruit.",
                "That was not the mission brief."
            ]
            let bodies = [
                "\(signed) since last. Not doom. Fix dinner tonight, not your personality.",
                "\(signed). Kitchen lights out. Protein first. No negotiation.",
                "\(signed) walked on. March it back with boring food and an early close."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 3),
                vibe.sergeantPop(seed: seed)
            )
        }
    }

    private static func encouragePack(
        who: String,
        delta: Double,
        towardIdeal: Double,
        vibe: PopCultureLens,
        seed: Int,
        gaining: Bool = false,
        unitSystem: PreferredUnitSystem = .metric,
        sex: UserBodyProfile.Sex = .male
    ) -> (headline: String, body: String, pop: String) {
        let signed = UnitFormat.massDeltaString(delta, system: unitSystem)
        let remain = UnitFormat.massString(max(0, towardIdeal), system: unitSystem, fractionDigits: 1)
        switch sex {
        case .female:
            if gaining {
                let headlines = [
                    "Fuel landed beautifully, \(who).",
                    "Builder energy. Love that.",
                    "Up is the job today."
                ]
                let bodies = [
                    "\(signed). Keep eating like you mean the program. Palm of protein, steady plates.",
                    "\(signed) on the board. Repeat the boring wins. You're glowing."
                ]
                return (pick(headlines, seed: seed), pick(bodies, seed: seed &+ 2), vibe.encouragePop(seed: seed))
            }
            let headlines = [
                "\(signed). You're glowing, \(who).",
                "Winner energy: \(signed).",
                "Look at you, \(who).",
                "That's the number, and you're a star."
            ]
            let bodies = [
                "\(signed) since last. Keep the boring streak. Dream weight is still \(remain) away, and you're walking it.",
                "\(signed). You're a winner. Celebrate with protein and early lights, not chaos.",
                "\(signed) lighter. The plot is working. Stay delightfully dull on purpose."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 5),
                vibe.encouragePop(seed: seed)
            )
        case .male:
            if gaining {
                let headlines = [
                    "Up is the job, \(who).",
                    "Fuel landed.",
                    "That's a builder's number."
                ]
                let bodies = [
                    "\(signed). Keep eating like you mean the program.",
                    "\(signed) on the board. Repeat the boring wins."
                ]
                return (pick(headlines, seed: seed), pick(bodies, seed: seed &+ 2), vibe.encouragePop(seed: seed))
            }
            let headlines = [
                "\(signed). You're a winner, \(who).",
                "Winner board: \(signed).",
                "Minus sign locked. Parade for \(who).",
                "That's the number, \(who)."
            ]
            let bodies = [
                "\(signed) since last. Keep the boring streak. Ideal still \(remain) away.",
                "\(signed). You're a winner. Don't celebrate with chaos. Protein, then bed.",
                "\(signed) lighter. The plot is working. Stay dull on purpose."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 5),
                vibe.encouragePop(seed: seed)
            )
        }
    }

    private static func skepticalPack(
        who: String,
        delta: Double,
        vibe: PopCultureLens,
        seed: Int,
        unitSystem: PreferredUnitSystem,
        sex: UserBodyProfile.Sex
    ) -> (headline: String, body: String, pop: String) {
        let signed = UnitFormat.massDeltaString(delta, system: unitSystem)
        switch sex {
        case .female:
            let headlines = [
                "Hmm, \(who). Curious chapter.",
                "Plot twist pending, gently.",
                "Interesting. In a good way.",
                "Flat-ish. Tomorrow still votes."
            ]
            let bodies = [
                "\(signed). Noise happens. Palm of protein and close the kitchen on time. Proud you checked.",
                "\(signed). Not a parade, not a funeral. Do the boring reps with a smile.",
                "\(signed). Water, salt, or vibes. Tomorrow still counts, and so do you."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 7),
                vibe.skepticalPop(seed: seed)
            )
        case .male:
            let headlines = [
                "Sure, \(who). The kg are listening.",
                "Plot twist pending.",
                "Interesting. Define interesting.",
                "Flat-ish. The jury is still out."
            ]
            let bodies = [
                "\(signed). Noise happens. Hit protein and close the kitchen on time.",
                "\(signed). Not a parade, not a funeral. Do the boring reps.",
                "\(signed). Water, salt, or vibes. Tomorrow still counts."
            ]
            return (
                pick(headlines, seed: seed),
                pick(bodies, seed: seed &+ 7),
                vibe.skepticalPop(seed: seed)
            )
        }
    }

    // MARK: - Helpers

    private static func pick(_ lines: [String], seed: Int) -> String {
        guard !lines.isEmpty else { return "" }
        let idx = abs(seed) % lines.count
        return lines[idx]
    }

    private static func dayKey(now: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    private static func deterministicSeed(name: String, weighedKg: Double, dayKey: String) -> Int {
        var hash = 5381
        let blob = "\(name)|\(String(format: "%.2f", weighedKg))|\(dayKey)"
        for byte in blob.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return hash
    }
}

// MARK: - Pop culture lens from profile

private struct PopCultureLens: Equatable {
    var tags: [String]

    static func from(profile: UserBodyProfile?) -> PopCultureLens {
        guard let profile else { return PopCultureLens(tags: ["default"]) }
        let blob = [
            profile.culturalVibe,
            profile.location,
            profile.ethnicity,
            profile.preferredLanguage,
            profile.dietPreference.rawValue,
            profile.sex.rawValue
        ]
        .joined(separator: " ")
        .lowercased()

        var tags: [String] = []
        let band = CoachAgeBand.from(ageYears: profile.ageYears)
        tags.append("age:\(band.rawValue)")
        if blob.contains("filip") || blob.contains("manila") || blob.contains("tagalog") {
            tags.append("ph")
        }
        if blob.contains("french") || blob.contains("paris") || blob.contains("france") {
            tags.append("fr")
        }
        if blob.contains("hong kong") || blob.contains("hk") || blob.contains("cantonese") {
            tags.append("hk")
        }
        if blob.contains("japan") || blob.contains("tokyo") || blob.contains("anime") {
            tags.append("jp")
        }
        if blob.contains("korean") || blob.contains("seoul") || blob.contains("k-pop") || blob.contains("kpop") {
            tags.append("kr")
        }
        if blob.contains("american") || blob.contains("usa") || blob.contains("hollywood") || blob.contains("marvel") {
            tags.append("us")
        }
        if blob.contains("british") || blob.contains("london") || blob.contains("uk") {
            tags.append("uk")
        }
        if blob.contains("vegan") || blob.contains("vegetarian") {
            tags.append("plant")
        }
        if tags.filter({ !$0.hasPrefix("age:") }).isEmpty { tags.append("default") }
        return PopCultureLens(tags: tags)
    }

    func sergeantPop(seed: Int) -> String {
        let lines: [String]
        if tags.contains("ph") {
            lines = [
                "This isn't Eat Bulaga, recruit. The scale kept score.",
                "Walang 'one more lumpia' tonight. Mission first."
            ]
        } else if tags.contains("fr") {
            lines = [
                "Sacré bleu is not a meal plan. Close the kitchen.",
                "Marie Antoinette energy detected. Let them eat protein."
            ]
        } else if tags.contains("jp") {
            lines = [
                "Main character arc rejected. Train like it's shonen week one.",
                "Not today, snack demon. Bankai the leftovers into the bin."
            ]
        } else if tags.contains("kr") {
            lines = [
                "No encore for late-night snacks. Comeback stage needs discipline.",
                "That was not the choreography. Reset the setlist at dinner."
            ]
        } else if tags.contains("hk") {
            lines = [
                "MTR closed. Kitchen closes too. March home without the cha chaan teng detour.",
                "Central isn't forgiving. Neither is the kg."
            ]
        } else if tags.contains("uk") {
            lines = [
                "Keep calm and stop raiding the biscuit tin.",
                "This isn't Bake Off. Step away from the sponge."
            ]
        } else if tags.contains("us") {
            lines = [
                "Rocky didn't hit the fridge after round twelve.",
                "Avengers assemble... at the gym. Not the drive-thru."
            ]
        } else {
            lines = [
                "Sergeant Scale has entered the chat.",
                "Drop the vibes. Pick up the fork schedule."
            ]
        }
        return pick(lines, seed: seed)
    }

    func encouragePop(seed: Int) -> String {
        let lines: [String]
        if tags.contains("ph") {
            lines = [
                "Quiet flex. Even your tita would side-eye less.",
                "Plot armour: boring meals. Keep it."
            ]
        } else if tags.contains("fr") {
            lines = [
                "Très chic restraint. Amélie would nod once and move on.",
                "Michelin star for not improvising dessert."
            ]
        } else if tags.contains("jp") {
            lines = [
                "Training montage unlocked. Keep the arc clean.",
                "Sensei Scale says: continue."
            ]
        } else if tags.contains("kr") {
            lines = [
                "Comeback trailer looks expensive. Stay on script.",
                "That was a title-track weigh-in. No B-sides tonight."
            ]
        } else if tags.contains("hk") {
            lines = [
                "Harbour view energy without the buffet plot twist.",
                "Peak tram discipline. Stay elevated."
            ]
        } else if tags.contains("uk") {
            lines = [
                "Stiff upper lip, softer midsection. Carry on.",
                "Bond villain plot denied. You kept the volume down."
            ]
        } else if tags.contains("us") {
            lines = [
                "Endgame energy without the snack infinity stones.",
                "That's a post-credit scene worth keeping."
            ]
        } else if tags.contains("plant") {
            lines = [
                "Plants did their job. You did yours. No victory pizza required.",
                "Chlorophyll and discipline. Elite combo."
            ]
        } else {
            lines = [
                "Physics sent a high-five. Don't reply with cake.",
                "Boring wins compound. Stay dull on purpose."
            ]
        }
        return pick(lines, seed: seed &+ 11)
    }

    func skepticalPop(seed: Int) -> String {
        let lines: [String]
        if tags.contains("ph") {
            lines = [
                "Hmm. Like a teleserye cliffhanger. Resolve it at dinner.",
                "The kg raised one eyebrow. Tagalog for 'prove it tomorrow'."
            ]
        } else if tags.contains("fr") {
            lines = [
                "Bof. The scale shrugged in French.",
                "J'accuse... the sodium. Or the vibes. Investigate."
            ]
        } else if tags.contains("jp") {
            lines = [
                "Filler episode energy. Tomorrow needs plot.",
                "Narrator voice: it was, in fact, not that deep. Yet."
            ]
        } else if tags.contains("kr") {
            lines = [
                "Mid-season hiatus vibes. Don't ghost the protein.",
                "The fandom wants receipts. Kitchen closes on time."
            ]
        } else if tags.contains("us") {
            lines = [
                "Sure, Jan. The kg took notes.",
                "Schrodinger's progress. Open the fridge carefully."
            ]
        } else if tags.contains("uk") {
            lines = [
                "Right then. Very interesting. Carry on, but less biscuits.",
                "The weather of your weigh-in: cloudy with a chance of discipline."
            ]
        } else {
            lines = [
                "The plot thickens by 0.0-something. Keep cooking boring.",
                "Side-eye deployed. Tomorrow still gets a vote."
            ]
        }
        return pick(lines, seed: seed &+ 17)
    }

    func baselinePop(seed: Int) -> String {
        let lines = [
            "Origin story framed. Sequel starts at the next step-on.",
            "Character sheet saved. Now play the level.",
            "Pilot episode in the can. Don't cancel the series with snacks."
        ]
        return pick(lines, seed: seed)
    }

    private func pick(_ lines: [String], seed: Int) -> String {
        guard !lines.isEmpty else { return "" }
        return lines[abs(seed) % lines.count]
    }
}

/// Pace projection to dream / ideal weight. Female copy avoids "ETA" jargon.
struct MacroGoalETA: Equatable, Sendable {
    var paceKgPerWeek: Double?
    var etaDate: Date?
    var plannedDate: Date?
    var remainingKg: Double
    var line: String
    /// Goal date cannot be hit inside the safe weekly cap.
    var needsDateRevision: Bool = false
    /// Earliest date Keel will pre-select when the goal is unrealistic.
    var proposedGoalDate: Date? = nil

    static func empty(sex: UserBodyProfile.Sex = .male) -> MacroGoalETA {
        MacroGoalETA(
            paceKgPerWeek: nil,
            etaDate: nil,
            plannedDate: nil,
            remainingKg: 0,
            line: CoachVoice.emptyPaceLine(sex: sex)
        )
    }

    static let empty = MacroGoalETA.empty(sex: .male)

    static func compute(
        currentKg: Double?,
        idealKg: Double,
        plannedDate: Date?,
        recentWeights: [HealthWeightSample],
        weeklyDeltaKg: Double,
        sex: UserBodyProfile.Sex = .male,
        unitSystem: PreferredUnitSystem = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MacroGoalETA {
        guard let current = currentKg else { return .empty(sex: sex) }
        let remaining = current - idealKg
        if abs(remaining) < 0.15 {
            return MacroGoalETA(
                paceKgPerWeek: 0,
                etaDate: now,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: CoachVoice.atGoalLine(sex: sex)
            )
        }
        if let plannedDate {
            let verdict = GoalPaceGuard.evaluate(
                currentKg: current,
                targetKg: idealKg,
                goalDate: plannedDate,
                now: now,
                calendar: calendar
            )
            if verdict.status == .rejected {
                let proposed = verdict.earliestFeasibleDate ?? plannedDate
                return MacroGoalETA(
                    paceKgPerWeek: verdict.requiredKgPerWeek,
                    etaDate: proposed,
                    plannedDate: plannedDate,
                    remainingKg: remaining,
                    line: CoachVoice.unrealisticDateLine(
                        remainingAbsKg: abs(remaining),
                        planText: Self.dateStamp(plannedDate),
                        proposedText: Self.dateStamp(proposed),
                        sex: sex,
                        unitSystem: unitSystem
                    ),
                    needsDateRevision: true,
                    proposedGoalDate: proposed
                )
            }
            let weeks = max(
                Double(calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: plannedDate)
                ).day ?? 0) / 7.0,
                1.0 / 7.0
            )
            let planPace = remaining / weeks
            return MacroGoalETA(
                paceKgPerWeek: planPace,
                etaDate: plannedDate,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: CoachVoice.onPlanLine(
                    remainingAbsKg: abs(remaining),
                    paceKgPerWeek: planPace,
                    planText: Self.dateStamp(plannedDate),
                    sex: sex,
                    unitSystem: unitSystem
                )
            )
        }

        // No goal date: project from observed pace, else the weekly mini-goal.
        var pace: Double?
        let sorted = recentWeights.sorted { $0.date < $1.date }
        if sorted.count >= 2,
           let first = sorted.first,
           let last = sorted.last {
            let days = max(1.0, last.date.timeIntervalSince(first.date) / 86_400)
            if days >= 3 {
                let delta = last.weightKg - first.weightKg
                pace = delta / days * 7.0
            }
        }
        if pace == nil {
            pace = weeklyDeltaKg
        }
        guard let paceKgPerWeek = pace, abs(paceKgPerWeek) > 0.02 else {
            let plannedBit = plannedDate.map {
                " Planned " + $0.formatted(.dateTime.month(.abbreviated).day()) + "."
            } ?? ""
            return MacroGoalETA(
                paceKgPerWeek: pace,
                etaDate: nil,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: CoachVoice.flatPaceLine(
                    remainingAbsKg: abs(remaining),
                    plannedBit: plannedBit,
                    sex: sex,
                    unitSystem: unitSystem
                )
            )
        }

        // Need pace in the right direction toward ideal.
        let towardIdeal = remaining > 0 // need to lose
        let movingRight = towardIdeal ? paceKgPerWeek < 0 : paceKgPerWeek > 0
        guard movingRight else {
            return MacroGoalETA(
                paceKgPerWeek: paceKgPerWeek,
                etaDate: nil,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: CoachVoice.wrongWayPaceLine(
                    remainingAbsKg: abs(remaining),
                    paceKgPerWeek: paceKgPerWeek,
                    sex: sex,
                    unitSystem: unitSystem
                )
            )
        }

        let weeks = abs(remaining / paceKgPerWeek)
        let eta = calendar.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: now)
        let etaText = eta.map(Self.dateStamp) ?? "soon"
        let plannedBit: String = {
            guard let planned = plannedDate else { return "" }
            let planText = Self.dateStamp(planned)
            if let eta, eta <= planned {
                return sex == .female
                    ? " Ahead of your plan (\(planText))."
                    : " Ahead of plan (\(planText))."
            }
            return sex == .female
                ? " Your plan said \(planText)."
                : " Plan was \(planText)."
        }()

        return MacroGoalETA(
            paceKgPerWeek: paceKgPerWeek,
            etaDate: eta,
            plannedDate: plannedDate,
            remainingKg: remaining,
            line: CoachVoice.paceLine(
                remainingAbsKg: abs(remaining),
                paceKgPerWeek: paceKgPerWeek,
                etaText: etaText,
                plannedBit: plannedBit,
                sex: sex,
                unitSystem: unitSystem
            )
        )
    }

    private static func dateStamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
