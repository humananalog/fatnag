import Foundation

/// Suggested dream body-fat % from sex + age. Optional override stays within physics clamps.
enum BodyFatTargetEngine {
    /// ACSM-style fitness targets (not medical). Used when the user leaves dream fat blank.
    static func suggestedIdealPercent(sex: UserBodyProfile.Sex, ageYears: Double) -> Double {
        let age = ageYears.isFinite ? ageYears : 30
        switch sex {
        case .male:
            if age < 40 { return 15 }
            if age < 60 { return 18 }
            return 21
        case .female:
            if age < 40 { return 23 }
            if age < 60 { return 26 }
            return 29
        }
    }

    /// Effective target for charts / coaching: override when set, else suggestion.
    static func effectiveIdealPercent(
        stored: Double?,
        sex: UserBodyProfile.Sex,
        ageYears: Double
    ) -> Double {
        if let stored, let clamped = ProfileNumericBounds.clampOptionalBodyFatPercent(stored).value {
            return clamped
        }
        return suggestedIdealPercent(sex: sex, ageYears: ageYears)
    }
}
