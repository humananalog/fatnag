import Foundation

/// A weight or body-fat goal the user stated in Coach chat.
enum CoachStatedTarget: Equatable, Sendable {
    case weightKg(Double)
    case bodyFatPercent(Double)
}

/// Result of checking a stated target against height/sex/current composition.
struct TargetFeasibilityResult: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        /// Safe enough to store on the profile.
        case accepted
        /// Stored, but Coach should mention the caution.
        case acceptedWithCaution
        /// Not stored. Coach must push back with a realistic alternative.
        case rejected
    }

    let verdict: Verdict
    let stated: CoachStatedTarget
    /// Applied weight when accepted (kg).
    let appliedWeightKg: Double?
    /// Applied body fat % when accepted.
    let appliedBodyFatPercent: Double?
    /// Safer alternative when rejected or cautioned.
    let suggestedWeightKg: Double?
    let suggestedBodyFatPercent: Double?
    /// BMI of stated weight when relevant.
    let statedBMI: Double?
    /// Short Coach bubble (no medical disclaimer spam).
    let coachNote: String
}

/// Parse + gate Coach-stated targets. Educational feasibility only (not a diagnosis).
enum TargetFeasibility {
    /// WHO-ish adult BMI bands used as soft gates (kg/m²).
    static let bmiUnderweight = 18.5
    static let bmiHealthyUpper = 24.9
    static let bmiObese = 30.0
    /// Hard reject below this BMI for a *target* (dangerously thin).
    static let bmiHardFloor = 16.0
    /// Hard reject above this as a *goal* (nonsensical / harmful direction).
    static let bmiHardCeiling = 45.0

    /// Essential / very-low floors by sex (ACE / sports-medicine ballparks).
    static func essentialBodyFatFloor(sex: UserBodyProfile.Sex) -> Double {
        switch sex {
        case .male: return 5.0
        case .female: return 12.0
        }
    }

    static func athleticBodyFatLow(sex: UserBodyProfile.Sex) -> Double {
        switch sex {
        case .male: return 8.0
        case .female: return 16.0
        }
    }

    static func realisticBodyFatBand(sex: UserBodyProfile.Sex) -> ClosedRange<Double> {
        switch sex {
        case .male: return 10.0...22.0
        case .female: return 18.0...32.0
        }
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = max(heightCm, 100) / 100.0
        return weightKg / (m * m)
    }

    static func weightKg(forBMI bmi: Double, heightCm: Double) -> Double {
        let m = max(heightCm, 100) / 100.0
        return (bmi * m * m).rounded(toPlaces: 1)
    }

    /// Max sustainable loss toward a lower target.
    ///
    /// **Rationale:** adult weight-management guidance commonly cites about
    /// **0.5–1% of body weight per week** as a sustainable loss band for people
    /// without specialized medical supervision (ACSM / obesity-medicine ballparks;
    /// similar ranges appear in clinical lifestyle programs). We use ~0.7%/wk
    /// (midpoint), then clamp to **0.25–1.0 kg/wk** so very light or heavy frames
    /// stay in a sane absolute band. Educational feasibility only — not a prescription.
    static func maxSafeLossKgPerWeek(currentKg: Double) -> Double {
        let pct = max(currentKg, 40) * 0.007 // ~0.7%/wk midpoint of 0.5–1%
        return min(max(pct, 0.25), 1.0)
    }

    /// Modest surplus for intentional gain: ~0.5%/wk, capped at 0.5 kg/wk.
    static func maxSafeGainKgPerWeek(currentKg: Double) -> Double {
        let pct = max(currentKg, 40) * 0.005
        return min(max(pct, 0.15), 0.5)
    }

    static func evaluate(
        stated: CoachStatedTarget,
        profile: UserBodyProfile,
        currentKg: Double?,
        currentBodyFatPercent: Double?
    ) -> TargetFeasibilityResult {
        switch stated {
        case .weightKg(let kg):
            return evaluateWeight(kg, profile: profile, currentKg: currentKg)
        case .bodyFatPercent(let pct):
            return evaluateBodyFat(pct, profile: profile, currentKg: currentKg, currentBodyFatPercent: currentBodyFatPercent)
        }
    }

    private static func evaluateWeight(
        _ kg: Double,
        profile: UserBodyProfile,
        currentKg: Double?
    ) -> TargetFeasibilityResult {
        let stated = CoachStatedTarget.weightKg(kg)
        guard kg.isFinite, kg >= 30, kg <= 300 else {
            return TargetFeasibilityResult(
                verdict: .rejected,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: UserBodyProfile.suggestedIdealWeightKg(heightCm: profile.heightCm),
                suggestedBodyFatPercent: nil,
                statedBMI: nil,
                coachNote: "That weight number is nonsense on a human frame. Pick something between roughly 30 and 300 kg."
            )
        }

        let bmi = Self.bmi(weightKg: kg, heightCm: profile.heightCm)
        let healthyLow = weightKg(forBMI: bmiUnderweight, heightCm: profile.heightCm)
        let healthyHigh = weightKg(forBMI: bmiHealthyUpper, heightCm: profile.heightCm)
        let suggested = UserBodyProfile.suggestedIdealWeightKg(heightCm: profile.heightCm)

        if bmi < bmiHardFloor {
            return TargetFeasibilityResult(
                verdict: .rejected,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: healthyLow,
                suggestedBodyFatPercent: nil,
                statedBMI: bmi,
                coachNote: String(
                    format: "%.1f kg is about BMI %.1f for your height. That is dangerously thin as a target. A safer floor is around %.1f kg (BMI %.1f). Not storing that.",
                    kg, bmi, healthyLow, bmiUnderweight
                )
            )
        }

        if bmi > bmiHardCeiling {
            return TargetFeasibilityResult(
                verdict: .rejected,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: min(suggested, healthyHigh),
                suggestedBodyFatPercent: nil,
                statedBMI: bmi,
                coachNote: String(
                    format: "%.1f kg is about BMI %.1f. As a *goal* that is not medically sensible. Try nearer %.1f kg first.",
                    kg, bmi, suggested
                )
            )
        }

        if let current = currentKg, abs(current - kg) > 0.05 {
            let delta = kg - current
            let weeksIfAggressive = abs(delta) / maxSafeLossKgPerWeek(currentKg: current)
            if delta < -0.05, weeksIfAggressive > 104 {
                let tempered = current - maxSafeLossKgPerWeek(currentKg: current) * 26
                return TargetFeasibilityResult(
                    verdict: .acceptedWithCaution,
                    stated: stated,
                    appliedWeightKg: kg,
                    appliedBodyFatPercent: nil,
                    suggestedWeightKg: tempered.rounded(toPlaces: 1),
                    suggestedBodyFatPercent: nil,
                    statedBMI: bmi,
                    coachNote: String(
                        format: "Target set to %.1f kg (BMI %.1f). From %.1f kg that is a long road at a safe ~%.1f kg/week. Near-term waypoint: ~%.1f kg in ~6 months. Charts will use %.1f kg.",
                        kg, bmi, current, maxSafeLossKgPerWeek(currentKg: current), tempered, kg
                    )
                )
            }
        }

        if bmi < bmiUnderweight {
            return TargetFeasibilityResult(
                verdict: .acceptedWithCaution,
                stated: stated,
                appliedWeightKg: kg,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: healthyLow,
                suggestedBodyFatPercent: nil,
                statedBMI: bmi,
                coachNote: String(
                    format: "Target set to %.1f kg (BMI %.1f). That sits under the usual adult healthy band. If energy, periods, or training tank, raise the floor toward %.1f kg.",
                    kg, bmi, healthyLow
                )
            )
        }

        if bmi >= bmiObese, let current = currentKg, kg >= current - 0.2 {
            return TargetFeasibilityResult(
                verdict: .acceptedWithCaution,
                stated: stated,
                appliedWeightKg: kg,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: suggested,
                suggestedBodyFatPercent: nil,
                statedBMI: bmi,
                coachNote: String(
                    format: "Target set to %.1f kg (BMI %.1f). Fine as a waypoint, but a stepwise target nearer %.1f kg is easier to defend medically.",
                    kg, bmi, suggested
                )
            )
        }

        return TargetFeasibilityResult(
            verdict: .accepted,
            stated: stated,
            appliedWeightKg: kg,
            appliedBodyFatPercent: nil,
            suggestedWeightKg: nil,
            suggestedBodyFatPercent: nil,
            statedBMI: bmi,
            coachNote: String(format: "Target weight updated to %.1f kg (BMI %.1f). History charts will use this line.", kg, bmi)
        )
    }

    private static func evaluateBodyFat(
        _ pct: Double,
        profile: UserBodyProfile,
        currentKg: Double?,
        currentBodyFatPercent: Double?
    ) -> TargetFeasibilityResult {
        let stated = CoachStatedTarget.bodyFatPercent(pct)
        let floor = essentialBodyFatFloor(sex: profile.sex)
        let athletic = athleticBodyFatLow(sex: profile.sex)
        let band = realisticBodyFatBand(sex: profile.sex)
        let sexWord = profile.sex == .female ? "female" : "male"

        guard pct.isFinite, pct > 0, pct < 70 else {
            return TargetFeasibilityResult(
                verdict: .rejected,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: nil,
                suggestedBodyFatPercent: band.lowerBound,
                statedBMI: nil,
                coachNote: "That body-fat number is not a usable human target."
            )
        }

        if pct < floor {
            return TargetFeasibilityResult(
                verdict: .rejected,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: nil,
                suggestedWeightKg: nil,
                suggestedBodyFatPercent: athletic,
                statedBMI: nil,
                coachNote: String(
                    format: "%.0f%% body fat is below essential stores for a typical %@ adult (~%.0f%% floor). Not storing that. A hard-athlete band starts nearer %.0f%%. Pick something in %.0f–%.0f%% unless a clinician is in the loop.",
                    pct, sexWord, floor, athletic, band.lowerBound, band.upperBound
                )
            )
        }

        if let current = currentBodyFatPercent, current - pct >= 15 {
            let waypoint = max(pct, current - 8)
            let note: String
            if pct < athletic {
                note = String(
                    format: "%.0f%% from ~%.0f%% is a huge cut into the athletic cellar. Not storing %.0f%%. Try a waypoint near %.0f%% first, then reassess.",
                    pct, current, pct, waypoint
                )
                return TargetFeasibilityResult(
                    verdict: .rejected,
                    stated: stated,
                    appliedWeightKg: nil,
                    appliedBodyFatPercent: nil,
                    suggestedWeightKg: nil,
                    suggestedBodyFatPercent: waypoint.rounded(toPlaces: 1),
                    statedBMI: nil,
                    coachNote: note
                )
            }
            return TargetFeasibilityResult(
                verdict: .acceptedWithCaution,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: pct,
                suggestedWeightKg: nil,
                suggestedBodyFatPercent: waypoint.rounded(toPlaces: 1),
                statedBMI: nil,
                coachNote: String(
                    format: "Body-fat target set to %.1f%% (from ~%.0f%%). That is aggressive. Near-term waypoint ~%.1f%% is more realistic. Scale BIA is noisy; trust multi-week trends.",
                    pct, current, waypoint
                )
            )
        }

        if pct < athletic {
            return TargetFeasibilityResult(
                verdict: .acceptedWithCaution,
                stated: stated,
                appliedWeightKg: nil,
                appliedBodyFatPercent: pct,
                suggestedWeightKg: nil,
                suggestedBodyFatPercent: band.lowerBound,
                statedBMI: nil,
                coachNote: String(
                    format: "Body-fat target set to %.1f%%. That is contest/athlete territory for %@ adults. Performance, hormones, and mood get a vote. Charts updated.",
                    pct, sexWord
                )
            )
        }

        return TargetFeasibilityResult(
            verdict: .accepted,
            stated: stated,
            appliedWeightKg: nil,
            appliedBodyFatPercent: pct,
            suggestedWeightKg: nil,
            suggestedBodyFatPercent: nil,
            statedBMI: nil,
            coachNote: String(format: "Body-fat target updated to %.1f%%. Fat chart will draw this Ideal line.", pct)
        )
    }
}

/// Pull explicit weight / body-fat goals out of Coach chat (on-device, no network).
enum CoachTargetExtractor {
    static func extract(from userText: String) -> [CoachStatedTarget] {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return [] }
        let lower = text.lowercased()
        var out: [CoachStatedTarget] = []

        let weightIntent =
            lower.contains("target") || lower.contains("goal") || lower.contains("ideal")
            || lower.contains("want to") || lower.contains("get to") || lower.contains("get down")
            || lower.contains("weigh") || lower.contains("down to") || lower.contains("up to")
            || lower.contains("aim for") || lower.contains("aiming") || lower.contains("set my")
            || lower.contains("make my") || lower.contains("reach ")

        let fatIntent =
            lower.contains("body fat") || lower.contains("bodyfat") || lower.contains("bf%")
            || lower.contains("fat %") || lower.contains("fat%") || lower.contains("bf %")

        if weightIntent || lower.contains("kg") || lower.contains("kilo") {
            for match in matches(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:kg|kilos|kilograms)\b"#) {
                if let value = Double(match), value >= 30, value <= 300 {
                    // Prefer weight when both kg and intent; avoid reading "80" from "80%".
                    out.append(.weightKg(value))
                }
            }
        }

        if fatIntent || lower.contains("%") {
            for match in matches(in: text, pattern: #"(\d+(?:\.\d+)?)\s*%"#) {
                if let value = Double(match), value > 0, value < 70 {
                    // Skip if this % was clearly a non-fat context (e.g. "100% sure") — weak filter:
                    if lower.contains("sure") && !fatIntent { continue }
                    out.append(.bodyFatPercent(value))
                }
            }
            // "body fat 18" without percent sign
            for match in matches(in: lower, pattern: #"body\s*fat(?:\s*%|\s*percent)?[^\d]{0,12}(\d+(?:\.\d+)?)"#) {
                if let value = Double(match), value > 0, value < 70 {
                    if !out.contains(.bodyFatPercent(value)) {
                        out.append(.bodyFatPercent(value))
                    }
                }
            }
        }

        // "target weight 80" without unit (assume kg when intent is clear)
        if weightIntent, out.filter({ if case .weightKg = $0 { return true }; return false }).isEmpty {
            for match in matches(in: lower, pattern: #"(?:target|goal|ideal)\s*(?:weight|wt)?\s*(?:is|=|:)?\s*(\d+(?:\.\d+)?)"#) {
                if let value = Double(match), value >= 30, value <= 300 {
                    out.append(.weightKg(value))
                }
            }
        }

        return dedupe(out)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func dedupe(_ items: [CoachStatedTarget]) -> [CoachStatedTarget] {
        var seenWeight = Set<String>()
        var seenFat = Set<String>()
        var out: [CoachStatedTarget] = []
        for item in items {
            switch item {
            case .weightKg(let kg):
                let key = String(format: "%.2f", kg)
                if seenWeight.insert(key).inserted { out.append(item) }
            case .bodyFatPercent(let pct):
                let key = String(format: "%.2f", pct)
                if seenFat.insert(key).inserted { out.append(item) }
            }
        }
        return out
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
