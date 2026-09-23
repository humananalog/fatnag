import Foundation

/// Shared clamps for Settings + onboarding numeric profile fields.
/// Rejects impossible values; callers show `message` when the user typed junk.
enum ProfileNumericBounds {
    static let ageYears = UserBodyProfile.minimumAgeYears...UserBodyProfile.maximumAgeYears
    /// Adult standing height (cm). ~3'11" to ~8'2".
    static let heightCm = 120.0...250.0
    /// Absolute mass floor/ceiling (kg). BMI gates still apply for dream weight.
    static let weightKg = 30.0...300.0
    /// Body fat % realistic adult range (essential floor ~3, extreme upper ~60).
    static let bodyFatPercent = 3.0...60.0
    /// Local morning drill must fire strictly before this hour.
    static let morningWeighDeadlineHour = 9

    struct ClampResult: Equatable, Sendable {
        let value: Double
        let didClamp: Bool
        let message: String?
    }

    static func clampAgeYears(_ raw: Double) -> ClampResult {
        guard raw.isFinite else {
            return ClampResult(value: 30, didClamp: true, message: "Age must be a number from 18 to 100.")
        }
        let rounded = raw.rounded()
        let clamped = min(ageYears.upperBound, max(ageYears.lowerBound, rounded))
        if clamped != rounded {
            return ClampResult(
                value: clamped,
                didClamp: true,
                message: "Age must be 18 to 100."
            )
        }
        return ClampResult(value: clamped, didClamp: false, message: nil)
    }

    static func clampHeightCm(_ raw: Double) -> ClampResult {
        guard raw.isFinite else {
            return ClampResult(value: 170, didClamp: true, message: "Height must be a real number.")
        }
        let clamped = min(heightCm.upperBound, max(heightCm.lowerBound, raw))
        if abs(clamped - raw) > 0.05 {
            return ClampResult(
                value: clamped,
                didClamp: true,
                message: "Height must be between \(Int(heightCm.lowerBound)) and \(Int(heightCm.upperBound)) cm."
            )
        }
        return ClampResult(value: clamped, didClamp: false, message: nil)
    }

    static func clampWeightKg(_ raw: Double) -> ClampResult {
        guard raw.isFinite else {
            return ClampResult(value: 70, didClamp: true, message: "Weight must be a real number.")
        }
        let clamped = min(weightKg.upperBound, max(weightKg.lowerBound, raw))
        if abs(clamped - raw) > 0.05 {
            return ClampResult(
                value: clamped,
                didClamp: true,
                message: weighRangeMessage
            )
        }
        return ClampResult(value: clamped, didClamp: false, message: nil)
    }

    /// True when kg is finite and inside absolute human mass bounds (not 0 / junk).
    /// Use for Health writes, auto-confirm, and hero. Calibration reference masses may be smaller.
    static func isPlausibleWeighKg(_ kg: Double) -> Bool {
        kg.isFinite && kg >= weightKg.lowerBound && kg <= weightKg.upperBound
    }

    /// Reject message for impossible live / manual / auto-confirm mass. Nil when ok.
    static func rejectWeighKgMessage(_ kg: Double) -> String? {
        guard !isPlausibleWeighKg(kg) else { return nil }
        if !kg.isFinite {
            return "Weight must be a real number."
        }
        if kg <= 0.05 {
            return "Weight must be greater than 0 kg."
        }
        return weighRangeMessage
    }

    private static var weighRangeMessage: String {
        String(
            format: "Weight must be between %.0f and %.0f kg (about %.0f-%.0f lb).",
            weightKg.lowerBound,
            weightKg.upperBound,
            weightKg.lowerBound * 2.20462,
            weightKg.upperBound * 2.20462
        )
    }

    /// Ideal / dream weight: absolute human bounds, then optional BMI-aware range.
    static func clampIdealWeightKg(
        _ raw: Double,
        heightCm: Double,
        currentKg: Double?
    ) -> ClampResult {
        let absolute = clampWeightKg(raw)
        var value = absolute.value
        var message = absolute.message
        let bounds = GoalPaceGuard.dreamWeightBoundsKg(
            currentKg: currentKg ?? value,
            heightCm: heightCm
        )
        let bmiClamped = min(bounds.upperBound, max(bounds.lowerBound, value))
        if abs(bmiClamped - value) > 0.05 {
            value = bmiClamped
            message = String(
                format: "Dream weight must stay in a realistic band for your height (about %.0f-%.0f kg).",
                bounds.lowerBound,
                bounds.upperBound
            )
        }
        return ClampResult(value: value, didClamp: absolute.didClamp || abs(bmiClamped - absolute.value) > 0.05, message: message)
    }

    /// Empty / blank → nil (optional field). Out of range → clamp + message. 0 / negative → nil with message.
    static func clampOptionalBodyFatPercent(_ raw: Double?) -> (value: Double?, message: String?) {
        guard let raw else { return (nil, nil) }
        guard raw.isFinite else {
            return (nil, "Body fat % must be a number, or leave blank if unknown.")
        }
        if raw <= 0.05 {
            return (nil, nil)
        }
        if raw < bodyFatPercent.lowerBound || raw > bodyFatPercent.upperBound {
            let clamped = min(bodyFatPercent.upperBound, max(bodyFatPercent.lowerBound, raw))
            return (
                clamped,
                String(
                    format: "Body fat %% must be between %.0f and %.0f. Leave blank if you do not know it.",
                    bodyFatPercent.lowerBound,
                    bodyFatPercent.upperBound
                )
            )
        }
        return (raw, nil)
    }

    /// Fallback morning clock must stay before 09:00 local.
    static func clampMorningFallback(hour: Int, minute: Int) -> (hour: Int, minute: Int) {
        var h = min(max(hour, 4), morningWeighDeadlineHour - 1)
        var m = min(max(minute, 0), 59)
        if hour >= morningWeighDeadlineHour {
            h = morningWeighDeadlineHour - 1
            m = 59
        }
        return (h, m)
    }

    /// True when `now` is still in the morning drill window (local hour strictly before 9).
    static func isBeforeMorningDeadline(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) < morningWeighDeadlineHour
    }
}
