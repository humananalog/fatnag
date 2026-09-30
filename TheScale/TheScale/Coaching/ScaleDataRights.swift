import Foundation

/// GDPR / CCPA data subject tools: export and erase on-device personal data.
enum ScaleDataRights {
    /// Keys owned by FATNAG in the app suite (UserDefaults.standard).
    static let appUserDefaultsKeys: [String] = [
        "thescale.userBodyProfile",
        "thescale.notificationPreferences",
        "thescale.weeklyMiniGoal",
        "thescale.hasCompletedOnboarding",
        "thescale.fitnessMonitorPreferences",
        "thescale.preferredUnitSystem",
        "thescale.scaleCalibration.v2",
        "thescale.coachMemoryFacts",
        "thescale.coachChatHistory.v1",
        "thescale.chartComments.v1",
        "thescale.mealPlan.v1",
        "thescale.mealPlan.v2",
        "thescale.mealPlan.v3",
        "thescale.profileGapPrompt.v1",
        "thescale.grokPrivacyConsentAccepted",
        "thescale.grokPrivacyConsentAcceptedAt",
        "thescale.legalAcceptedAt",
        "thescale.debugPlanOverride",
        "thescale.coachWeeklyQuota.count",
        "thescale.coachWeeklyQuota.week",
        "thescale.mondayCard.payload",
        "thescale.mondayCard.priorSundayTargetKg",
        "thescale.monthlyHero.payload",
        "thescale.review.successfulWeighIns",
        "thescale.review.lastPromptAt",
        "thescale.review.lastSoftDismissAt",
        "thescale.review.optedOutLowScore",
        "thescale.review.hasRequestedAppStoreReview",
        "thescale.anonymousUserId",
        "thescale.feedback.lastSoftAskAt",
        "thescale.feedback.lastSubmitAt",
        NotificationArchiveStore.storageKey
    ]

    /// JSON export of local preferences / profile / coach memory (no HealthKit bulk dump).
    static func exportLocalDataJSON(profile: UserBodyProfile) throws -> Data {
        var payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "controller": ScaleLegal.controllerName,
            "bundleId": ScaleStorefront.bundleID,
            "note": "Apple Health samples are not included. Export or delete Health data in the Health app if needed.",
            "profile": encodeJSONObject(profile) ?? [:],
            "coachPrivacyConsentAccepted": GrokPrivacyConsent.isAccepted,
            "coachPrivacyConsentAcceptedAt": GrokPrivacyConsent.acceptedAt.map {
                ISO8601DateFormatter().string(from: $0)
            } as Any,
            "legalAcceptedAt": LegalAcceptanceStore.acceptedAt.map {
                ISO8601DateFormatter().string(from: $0)
            } as Any,
            "coachMemoryFacts": encodeJSONObject(CoachMemoryStore.load()) ?? [],
            "notificationPreferences": encodeJSONObject(NotificationPreferencesStore.load()) ?? [:],
            "weeklyMiniGoal": encodeJSONObject(WeeklyMiniGoalStore.load()) ?? [:],
            "preferredUnits": PreferredUnitSystemStore.load().rawValue,
            "calibration": encodeJSONObject(ScaleCalibrationStore.load()) ?? [:],
            "fitnessMonitorPreferences": encodeJSONObject(FitnessMonitorPreferencesStore.load()) ?? [:]
        ]
        if let chatData = UserDefaults.standard.data(forKey: "thescale.coachChatHistory.v1"),
           let chatJSON = try? JSONSerialization.jsonObject(with: chatData) {
            payload["coachChatHistory"] = chatJSON
        }
        if let comments = UserDefaults.standard.data(forKey: "thescale.chartComments.v1"),
           let commentsJSON = try? JSONSerialization.jsonObject(with: comments) {
            payload["chartComments"] = commentsJSON
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// Wipe FATNAG local stores. Does not delete Apple Health samples (user must use Health app).
    @MainActor
    static func eraseAllLocalData(session: ScaleSessionViewModel) {
        for key in appUserDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        CoachMemoryStore.clear()
        CoachChatHistoryStore.clear()
        ChartCommentStore.clear()
        MealPlanStore.clear()
        ProfileGapPromptStore.clear()
        MondayCardStore.clear()
        GrokLegacyKeychain.clearUserEnteredKey()
        GrokPrivacyConsent.isAccepted = false

        session.profile = .default
        session.calibration = .default
        session.notificationPreferences = .default
        session.fitnessMonitorPreferences = .default
        session.weeklyGoal = .default
        session.preferredUnits = .metric
        session.clearMealPlanCache()
        session.hasCompletedOnboarding = false
        LegalAcceptanceStore.clear()
        #if DEBUG
        session.clearDemoPersonaLock()
        #endif
    }

    private static func encodeJSONObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

/// Records when the user accepted Terms + Privacy + Medical at onboarding (accountability).
enum LegalAcceptanceStore {
    private static let key = "thescale.legalAcceptedAt"

    static var acceptedAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: key)
            guard t > 0 else { return nil }
            return Date(timeIntervalSince1970: t)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static func markAccepted(now: Date = Date()) {
        acceptedAt = now
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
