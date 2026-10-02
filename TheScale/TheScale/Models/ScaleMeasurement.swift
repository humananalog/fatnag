import Foundation

/// Decoded BLE frame from a compatible body scale (brand/model via `sourceDeviceLabel`).
struct ScaleMeasurement: Equatable, Identifiable, Sendable {
    let id: UUID
    /// Weight in kilograms.
    let weightKg: Double
    /// Bioelectrical impedance in ohms, when the scale finished the BIA sweep.
    let impedanceOhms: Int?
    /// Scale-reported timestamp from the advertisement frame.
    let scaleDate: Date?
    /// Whether the frame included a valid impedance reading.
    let hasImpedance: Bool
    /// True when the scale set the impedance flag but ohms were not yet valid (BIA still running).
    let biaPending: Bool
    /// Unit the scale was configured to display (weight is always stored as kg).
    let displayUnit: ScaleWeightUnit
    let receivedAt: Date
    /// False for live settling frames shown while the scale is still locking weight.
    let isStabilized: Bool
    /// Decoder / hardware label for HealthKit metadata (generic when unknown).
    let sourceDeviceLabel: String

    init(
        id: UUID = UUID(),
        weightKg: Double,
        impedanceOhms: Int?,
        scaleDate: Date?,
        hasImpedance: Bool,
        biaPending: Bool = false,
        displayUnit: ScaleWeightUnit,
        receivedAt: Date = Date(),
        isStabilized: Bool = true,
        sourceDeviceLabel: String = "Bluetooth body scale"
    ) {
        self.id = id
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.scaleDate = scaleDate
        self.hasImpedance = hasImpedance
        self.biaPending = biaPending
        self.displayUnit = displayUnit
        self.receivedAt = receivedAt
        self.isStabilized = isStabilized
        self.sourceDeviceLabel = sourceDeviceLabel
    }
}

enum ScaleWeightUnit: String, Sendable {
    case kilogram
    case pound
    case catty
}

/// User profile needed to estimate body composition from impedance + coaching.
struct UserBodyProfile: Equatable, Codable, Sendable {
    /// Adults only. Onboarding and Settings reject ages below this.
    static let minimumAgeYears: Double = 18
    /// Inclusive upper bound for age controls (onboarding swipe + Settings).
    static let maximumAgeYears: Double = 100

    enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
        case female
        case male

        var id: String { rawValue }

        var title: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            }
        }
    }

    /// Preferred name for greetings and coach copy (on-device only).
    var displayName: String
    var heightCm: Double
    var ageYears: Double
    var sex: Sex
    /// Goal weight (kg). Used as the weight chart axis floor + ideal reference line.
    var idealWeightKg: Double
    /// Optional calendar date for hitting idealWeightKg. Used by Monday Sunday pacing.
    var goalDate: Date?
    /// Optional goal body fat %. When set, fat chart uses it as floor / reference.
    var idealBodyFatPercent: Double?
    /// Self-reported starting weight from onboarding (kg). Seeds weekly goal engines before Health has a sample.
    var startingWeightKg: Double?
    /// Optional self-reported body fat % at onboarding.
    var startingBodyFatPercent: Double?
    /// Medical situations, drugs, alcohol / habits. On-device Coach context only.
    var healthContextNotes: String
    /// Flavor tier title from dream-weight difficulty (e.g. Hell, Brat Mode). Caps still win over flavor.
    var goalDifficultyTitle: String?
    var dietPreference: DietPreference
    /// City / region for culturally aware coaching (on-device).
    var location: String
    /// Ethnicity or cultural background the user wants the coach to respect.
    var ethnicity: String
    /// Preferred spoken / written language for coach replies.
    var preferredLanguage: String
    /// Vibe / cultural style notes (e.g. Filipina in Manila; French in HK preferring American culture).
    var culturalVibe: String
    /// Allergies and hard nos for meal plans (peanuts, shellfish, no pork). Blank is fine.
    var foodAvoidances: String
    /// True after the user saves avoidances (including an explicit blank = none).
    var foodAvoidancesConfirmed: Bool
    /// When true, location informs local food / supermarket / nearby fitness suggestions.
    var useLocalContext: Bool
    /// False until the user explicitly picks a diet in onboarding or Settings.
    var dietPreferenceConfirmed: Bool
    /// Structured intermittent fasting window (`eatingWindowStart` / `eatingWindowEnd`). Nil = none.
    var intermittentFasting: FastingWindow?

    /// First name / greeting fragment; falls back to empty.
    var greetingName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    /// Compact persona lines for Grok system prompts (skips blanks).
    var coachPersonaBlock: String {
        var lines: [String] = []
        let ageInt = max(18, Int(ageYears.rounded()))
        let band = CoachAgeBand.from(ageYears: ageYears)
        lines.append("Age: \(ageInt) (\(band.promptLabel)) — match humour and references to this age.")
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let eth = ethnicity.trimmingCharacters(in: .whitespacesAndNewlines)
        let appLang = AppLanguageStore.current.resolved.profileLanguageName
        let profileLang = preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let vibe = culturalVibe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileLang.isEmpty {
            lines.append("Preferred language (mandatory reply language): \(profileLang)")
        } else if !appLang.isEmpty {
            lines.append("Preferred language (mandatory reply language): \(appLang)")
        }
        if !loc.isEmpty {
            let localBit = useLocalContext
                ? " (use for local markets, meal staples, nearby fitness, and local humour anchors)"
                : ""
            lines.append("Location: \(loc)\(localBit)")
        }
        if !eth.isEmpty {
            lines.append(
                "Ethnicity / culture: \(eth) (belonging + food/slang register only; never a punchline)"
            )
        }
        lines.append(AppLanguageStore.current.resolved.modelDirective)
        if !vibe.isEmpty { lines.append("Vibe / cultural style: \(vibe)") }
        lines.append("Diet preference: \(dietPreference.title)\(dietPreferenceConfirmed ? "" : " (unconfirmed)")")
        let avoid = foodAvoidances.trimmingCharacters(in: .whitespacesAndNewlines)
        if !avoid.isEmpty {
            lines.append("Food avoidances / allergies: \(avoid)")
        } else if foodAvoidancesConfirmed {
            lines.append("Food avoidances / allergies: none stated")
        }
        if let ifWindow = intermittentFasting, ifWindow.isActive {
            let open = MealPlanEngine.formatHour(ifWindow.eatingStartHour)
            let close = MealPlanEngine.formatHour(ifWindow.eatingEndHour)
            lines.append(
                "Intermittent fasting: \(ifWindow.protocolLabel) (\(ifWindow.fastingHours)h fast). Eating window \(open)-\(close) local (eatingWindowStart=\(ifWindow.eatingWindowStart), eatingWindowEnd=\(ifWindow.eatingWindowEnd))."
            )
        }
        let health = healthContextNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !health.isEmpty {
            lines.append("Health context (user-stated; not a diagnosis): \(health)")
        }
        if let difficulty = goalDifficultyTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !difficulty.isEmpty {
            lines.append("Goal difficulty flavor: \(difficulty). Respect safe weekly biology caps over flavor.")
        }
        if let start = startingWeightKg {
            lines.append(String(format: "Onboarding starting weight: %.1f kg", start))
        }
        lines.append(
            CoachVoice.cultureInsightPayload(
                ageYears: ageYears,
                location: location,
                ethnicity: ethnicity,
                culturalVibe: culturalVibe
            )
        )
        guard !lines.isEmpty else { return "" }
        return """
        Persona (match tone and examples to this; do not stereotype or exoticize):
        \(lines.joined(separator: "\n"))
        Reply fully in Preferred language when set. Subtle vulgar local jokes OK when rooted in language/location/vibe; never racist or ethnicity-as-punchline.
        """
    }

    static let `default` = UserBodyProfile(
        displayName: "",
        heightCm: 170,
        ageYears: 30,
        sex: .male,
        idealWeightKg: suggestedIdealWeightKg(heightCm: 170),
        goalDate: nil,
        idealBodyFatPercent: nil,
        startingWeightKg: nil,
        startingBodyFatPercent: nil,
        healthContextNotes: "",
        goalDifficultyTitle: nil,
        dietPreference: .omnivore,
        location: "",
        ethnicity: "",
        preferredLanguage: "English",
        culturalVibe: "",
        foodAvoidances: "",
        foodAvoidancesConfirmed: false,
        useLocalContext: true,
        dietPreferenceConfirmed: false,
        intermittentFasting: nil
    )

    /// BMI ~22 suggestion used when seeding a new profile or migrating old saves.
    static func suggestedIdealWeightKg(heightCm: Double) -> Double {
        let meters = max(heightCm, 100) / 100.0
        return (22.0 * meters * meters).rounded(toPlaces: 1)
    }

    init(
        displayName: String = "",
        heightCm: Double,
        ageYears: Double,
        sex: Sex,
        idealWeightKg: Double? = nil,
        goalDate: Date? = nil,
        idealBodyFatPercent: Double? = nil,
        startingWeightKg: Double? = nil,
        startingBodyFatPercent: Double? = nil,
        healthContextNotes: String = "",
        goalDifficultyTitle: String? = nil,
        dietPreference: DietPreference = .omnivore,
        location: String = "",
        ethnicity: String = "",
        preferredLanguage: String = "English",
        culturalVibe: String = "",
        foodAvoidances: String = "",
        foodAvoidancesConfirmed: Bool = false,
        useLocalContext: Bool = true,
        dietPreferenceConfirmed: Bool = false,
        intermittentFasting: FastingWindow? = nil
    ) {
        self.displayName = displayName
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
        self.idealWeightKg = idealWeightKg ?? Self.suggestedIdealWeightKg(heightCm: heightCm)
        self.goalDate = goalDate
        self.idealBodyFatPercent = idealBodyFatPercent
        self.startingWeightKg = startingWeightKg
        self.startingBodyFatPercent = startingBodyFatPercent
        self.healthContextNotes = healthContextNotes
        self.goalDifficultyTitle = goalDifficultyTitle
        self.dietPreference = dietPreference
        self.location = location
        self.ethnicity = ethnicity
        self.preferredLanguage = preferredLanguage
        self.culturalVibe = culturalVibe
        self.foodAvoidances = foodAvoidances
        self.foodAvoidancesConfirmed = foodAvoidancesConfirmed
        self.useLocalContext = useLocalContext
        self.dietPreferenceConfirmed = dietPreferenceConfirmed
        self.intermittentFasting = intermittentFasting
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        heightCm = try c.decode(Double.self, forKey: .heightCm)
        ageYears = try c.decode(Double.self, forKey: .ageYears)
        sex = try c.decode(Sex.self, forKey: .sex)
        idealWeightKg = try c.decodeIfPresent(Double.self, forKey: .idealWeightKg)
            ?? Self.suggestedIdealWeightKg(heightCm: heightCm)
        goalDate = try c.decodeIfPresent(Date.self, forKey: .goalDate)
        idealBodyFatPercent = try c.decodeIfPresent(Double.self, forKey: .idealBodyFatPercent)
        startingWeightKg = try c.decodeIfPresent(Double.self, forKey: .startingWeightKg)
        startingBodyFatPercent = try c.decodeIfPresent(Double.self, forKey: .startingBodyFatPercent)
        healthContextNotes = try c.decodeIfPresent(String.self, forKey: .healthContextNotes) ?? ""
        goalDifficultyTitle = try c.decodeIfPresent(String.self, forKey: .goalDifficultyTitle)
        dietPreference = try c.decodeIfPresent(DietPreference.self, forKey: .dietPreference) ?? .omnivore
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        ethnicity = try c.decodeIfPresent(String.self, forKey: .ethnicity) ?? ""
        preferredLanguage = try c.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? "English"
        culturalVibe = try c.decodeIfPresent(String.self, forKey: .culturalVibe) ?? ""
        foodAvoidances = try c.decodeIfPresent(String.self, forKey: .foodAvoidances) ?? ""
        foodAvoidancesConfirmed = try c.decodeIfPresent(Bool.self, forKey: .foodAvoidancesConfirmed) ?? false
        useLocalContext = try c.decodeIfPresent(Bool.self, forKey: .useLocalContext) ?? true
        dietPreferenceConfirmed = try c.decodeIfPresent(Bool.self, forKey: .dietPreferenceConfirmed) ?? false
        intermittentFasting = try c.decodeIfPresent(FastingWindow.self, forKey: .intermittentFasting)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(heightCm, forKey: .heightCm)
        try c.encode(ageYears, forKey: .ageYears)
        try c.encode(sex, forKey: .sex)
        try c.encode(idealWeightKg, forKey: .idealWeightKg)
        try c.encodeIfPresent(goalDate, forKey: .goalDate)
        try c.encodeIfPresent(idealBodyFatPercent, forKey: .idealBodyFatPercent)
        try c.encodeIfPresent(startingWeightKg, forKey: .startingWeightKg)
        try c.encodeIfPresent(startingBodyFatPercent, forKey: .startingBodyFatPercent)
        try c.encode(healthContextNotes, forKey: .healthContextNotes)
        try c.encodeIfPresent(goalDifficultyTitle, forKey: .goalDifficultyTitle)
        try c.encode(dietPreference, forKey: .dietPreference)
        try c.encode(location, forKey: .location)
        try c.encode(ethnicity, forKey: .ethnicity)
        try c.encode(preferredLanguage, forKey: .preferredLanguage)
        try c.encode(culturalVibe, forKey: .culturalVibe)
        try c.encode(foodAvoidances, forKey: .foodAvoidances)
        try c.encode(foodAvoidancesConfirmed, forKey: .foodAvoidancesConfirmed)
        try c.encode(useLocalContext, forKey: .useLocalContext)
        try c.encode(dietPreferenceConfirmed, forKey: .dietPreferenceConfirmed)
        try c.encodeIfPresent(intermittentFasting, forKey: .intermittentFasting)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, heightCm, ageYears, sex, idealWeightKg, goalDate, idealBodyFatPercent
        case startingWeightKg, startingBodyFatPercent, healthContextNotes, goalDifficultyTitle
        case dietPreference, location, ethnicity, preferredLanguage, culturalVibe
        case foodAvoidances, foodAvoidancesConfirmed, useLocalContext, dietPreferenceConfirmed
        case intermittentFasting
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

/// Body composition derived on-device from weight + impedance + profile.
struct BodyCompositionResult: Equatable, Sendable {
    let bmi: Double
    let bodyFatPercent: Double
    let waterPercent: Double
    let boneMassKg: Double
    let muscleMassKg: Double
    let leanBodyMassKg: Double
    let visceralFat: Double
}
