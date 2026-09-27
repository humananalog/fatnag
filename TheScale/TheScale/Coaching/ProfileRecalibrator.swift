import Foundation

/// Recomputes gender-sensitive profile targets after sex (or related anatomy) changes.
enum ProfileRecalibrator {
    struct Result: Equatable, Sendable {
        var idealWeightKg: Double
        var idealBodyFatPercent: Double?
        var goalDifficultyTitle: String?
        var note: String
    }

    /// Clamp dream weight into the new sex BMI band; refresh suggested dream fat unless user overrode;
    /// retitle difficulty flavor for the new sex.
    static func recalibrate(
        profile: UserBodyProfile,
        currentKg: Double?,
        keepBodyFatOverride: Bool
    ) -> Result {
        let weight = ProfileNumericBounds.clampIdealWeightKg(
            profile.idealWeightKg,
            heightCm: profile.heightCm,
            currentKg: currentKg ?? profile.startingWeightKg,
            sex: profile.sex,
            ageYears: profile.ageYears
        )
        let suggestedFat = BodyFatTargetEngine.suggestedIdealPercent(
            sex: profile.sex,
            ageYears: profile.ageYears
        )
        let fat: Double?
        if keepBodyFatOverride, let stored = profile.idealBodyFatPercent {
            fat = ProfileNumericBounds.clampOptionalBodyFatPercent(stored).value
        } else {
            fat = nil
        }
        let level: Int = {
            guard let title = profile.goalDifficultyTitle else { return 0 }
            return GoalDifficultyFlavor.maleTitles.firstIndex(of: title)
                ?? GoalDifficultyFlavor.femaleTitles.firstIndex(of: title)
                ?? 0
        }()
        let band = GoalDifficultyFlavor.band(sex: profile.sex, level: level, ratio: nil)
        let fatNote = fat == nil
            ? String(format: "Suggested dream body fat %.0f%% for %@", suggestedFat, profile.sex.title.lowercased())
            : "Kept your body-fat override; rechecked physics limits"
        return Result(
            idealWeightKg: weight.value,
            idealBodyFatPercent: fat,
            goalDifficultyTitle: band.title,
            note: "Recalibrated for \(profile.sex.title.lowercased()). \(fatNote)."
        )
    }
}
