import XCTest
@testable import TheScale

final class CoachOfflineTests: XCTestCase {
    func testOfflineOrchestratorUsesName() {
        let brief = CoachBrief(
            userName: "Alex",
            diet: .omnivore,
            heightCm: 178,
            ageYears: 40,
            sex: .male,
            currentKg: 78,
            idealKg: 75,
            bodyFatPercent: 18,
            idealBodyFatPercent: 15,
            trend: .gain(deltaKg: 0.4),
            weekDeltaKg: 0.5,
            weeklyGoal: .default
        )
        let reply = CoachOfflineFallback.reply(role: .orchestrator, brief: brief)
        XCTAssertTrue(reply.text.contains("Alex"))
        XCTAssertFalse(reply.usedNetwork)
        XCTAssertTrue(reply.disclaimer.isEmpty)
        XCTAssertFalse(reply.text.lowercased().contains("not medical advice"))
    }

    func testCopySanitizeStripsEmDashAndDisclaimer() {
        let raw = "Hello — world\nNot medical advice. Talk to a real clinician."
        let cleaned = CoachCopySanitize.clean(raw)
        XCTAssertFalse(cleaned.contains("\u{2014}"))
        XCTAssertTrue(cleaned.contains("Hello - world") || cleaned.contains("Hello -world"))
        XCTAssertFalse(cleaned.lowercased().contains("not medical advice"))
    }

    func testParseSSEDeltaExtractsContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        XCTAssertEqual(GrokClient.parseSSEDelta(line: line), "Hi")
        XCTAssertNil(GrokClient.parseSSEDelta(line: "data: [DONE]"))
        XCTAssertNil(GrokClient.parseSSEDelta(line: "event: ping"))
    }

    func testBadTrendReasonFiresOnGainAboveIdeal() {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 76, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 77, date: Date(timeIntervalSince1970: day * 3)),
            HealthMetricSample(value: 78.2, date: Date(timeIntervalSince1970: day * 6))
        ]
        // Shift samples to "now"
        let now = Date()
        let recent = samples.map {
            HealthMetricSample(value: $0.value, date: now.addingTimeInterval($0.date.timeIntervalSince1970 - day * 6))
        }
        let reason = TrendNotificationScheduler.badTrendReason(
            currentKg: 78.2,
            idealKg: 75,
            recent: recent
        )
        XCTAssertNotNil(reason)
    }

    func testBadTrendQuietWhenNearIdeal() {
        let now = Date()
        let recent = [
            HealthMetricSample(value: 75.1, date: now.addingTimeInterval(-3 * 86_400)),
            HealthMetricSample(value: 75.2, date: now)
        ]
        let reason = TrendNotificationScheduler.badTrendReason(
            currentKg: 75.2,
            idealKg: 75,
            recent: recent
        )
        XCTAssertNil(reason)
    }

    func testProfileNameAndDietMigrate() throws {
        let legacy = """
        {"heightCm":180,"ageYears":40,"sex":"male"}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserBodyProfile.self, from: legacy)
        XCTAssertEqual(profile.displayName, "")
        XCTAssertEqual(profile.dietPreference, .omnivore)
    }

    func testWeeklyGoalProgress() throws {
        var goal = WeeklyMiniGoal.default
        goal.weekStartKg = 80
        goal.targetDeltaKg = -0.5
        let fraction = try XCTUnwrap(goal.progressFraction(currentKg: 79.75))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.01)
    }

    func testRatePerWeek() throws {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: day * 7))
        ]
        let rate = try XCTUnwrap(HealthChartMath.ratePerWeek(samples: samples))
        XCTAssertEqual(rate, -1.0, accuracy: 0.05)
    }

    func testRoutePicksMedical() {
        XCTAssertEqual(GrokClient.route(userText: "Is this chest pain bad?"), .medical)
    }

    func testRoutePicksFitness() {
        XCTAssertEqual(GrokClient.route(userText: "Should I lift today on a calorie cut?"), .fitness)
    }

    func testRouteDefaultsToOrchestrator() {
        XCTAssertEqual(GrokClient.route(userText: "How's my week looking?"), .orchestrator)
    }

    func testMemoryExtractorCapturesIntermittentFasting() {
        CoachMemoryStore.clear()
        let facts = CoachMemoryExtractor.extract(from: "I'm doing intermittent fasting 16/8")
        XCTAssertFalse(facts.isEmpty)
        for fact in facts {
            CoachMemoryStore.remember(fact)
        }
        let block = CoachMemoryStore.promptBlock()
        XCTAssertTrue(block.lowercased().contains("intermittent fasting") || block.contains("16/8"))
        CoachMemoryStore.clear()
    }

    func testPersonaBlockMigratesFromLegacyProfile() throws {
        let legacy = """
        {"heightCm":180,"ageYears":40,"sex":"male","displayName":"Alex"}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserBodyProfile.self, from: legacy)
        XCTAssertEqual(profile.preferredLanguage, "English")
        XCTAssertEqual(profile.location, "")
        XCTAssertTrue(profile.coachPersonaBlock.contains("English"))
        XCTAssertTrue(profile.coachPersonaBlock.contains("Language lock"))
        XCTAssertFalse(profile.coachPersonaBlock.contains("Manila"))
        XCTAssertFalse(profile.coachPersonaBlock.contains("Location:"))
        var filled = profile
        filled.location = "Manila"
        filled.ethnicity = "Filipina"
        filled.culturalVibe = "local food, straight talk"
        filled.preferredLanguage = "Tagalog"
        XCTAssertTrue(filled.coachPersonaBlock.contains("Manila"))
        XCTAssertTrue(filled.coachPersonaBlock.contains("Tagalog"))
        XCTAssertTrue(filled.coachPersonaBlock.lowercased().contains("never racist")
            || filled.coachPersonaBlock.lowercased().contains("ethnicity-as-punchline"))
    }

    func testPreSleepHRElevatedTrigger() {
        var digest = FitnessDigest.empty
        digest.sleepOnset = Date()
        digest.preSleepAverageHRBpm = 98
        digest.preSleepHRSampleCount = 12
        digest.restingHeartRateBpm = 60
        let triggers = FitnessTriggerMonitor.evaluate(digest: digest, thresholds: .default)
        XCTAssertTrue(triggers.contains(where: { $0.kind == .preSleepHRElevated }))
    }

    func testPreSleepHRMissingTrigger() {
        var digest = FitnessDigest.empty
        digest.sleepOnset = Date()
        digest.preSleepHRSampleCount = 0
        let triggers = FitnessTriggerMonitor.evaluate(digest: digest, thresholds: .default)
        XCTAssertTrue(triggers.contains(where: { $0.kind == .preSleepHRMissing }))
    }

    func testWatchNotWornTrigger() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 8_000
        digest.heartRateSampleCountToday = 1
        let triggers = FitnessTriggerMonitor.evaluate(digest: digest, thresholds: .default)
        XCTAssertTrue(triggers.contains(where: { $0.kind == .watchLikelyNotWorn }))
    }

    func testAutomatedCheckDueLogic() {
        var prefs = FitnessMonitorPreferences.default
        prefs.enabled = true
        prefs.interval = .daily
        prefs.lastAutomatedCheckAt = nil
        XCTAssertTrue(FitnessTriggerMonitor.isAutomatedCheckDue(prefs: prefs))
        prefs.lastAutomatedCheckAt = Date()
        XCTAssertFalse(FitnessTriggerMonitor.isAutomatedCheckDue(prefs: prefs))
    }

    func testXcconfigHttpsEscapeExpands() {
        // Document the footgun fix: https:/$()/host → https://host
        let escaped = "https:/$()/the-scale-grok.alexhuther.workers.dev"
        let expanded = escaped.replacingOccurrences(of: "$()", with: "")
        XCTAssertEqual(expanded, "https://the-scale-grok.alexhuther.workers.dev")
        let strippedComment: String = {
            let raw = "GROK_PROXY_URL = https://the-scale-grok.alexhuther.workers.dev"
            if let idx = raw.range(of: "//") {
                return String(raw[..<idx.lowerBound])
            }
            return raw
        }()
        XCTAssertTrue(strippedComment.contains("https:"))
        XCTAssertFalse(strippedComment.contains("workers.dev"))
    }

    func testSharedConfigStatusWithoutSecretsIsOffline() {
        // Bundle Info.plist in unit tests has empty / unset Grok keys or secret → offline path.
        XCTAssertFalse(GrokSharedConfig.isLiveConfigured)
        let summary = GrokSharedConfig.statusSummary.lowercased()
        XCTAssertTrue(
            summary.contains("offline")
                || summary.contains("no shared")
                || summary.contains("secret")
                || summary.contains("grok_app_secret")
        )
    }

    func testLanguageSettingValidatesAndLocksModels() {
        let key = "thescale.appLanguage"
        let prior = UserDefaults.standard.string(forKey: key)
        let priorApple = UserDefaults.standard.stringArray(forKey: "AppleLanguages")
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let priorApple {
                UserDefaults.standard.set(priorApple, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            AppLanguageStore.syncBundleLanguages(AppLanguageStore.current)
        }
        XCTAssertNil(AppLanguage.validated("Tagalog"))
        XCTAssertNil(AppLanguage.validated(" "))
        XCTAssertNil(AppLanguage.validated("nope"))
        XCTAssertEqual(AppLanguage.validated("fr"), .french)
        XCTAssertEqual(AppLanguageStore.apply(.french), .french)
        XCTAssertEqual(AppLanguageStore.current, .french)
        XCTAssertEqual(FatnagBrand.tagline, "Nag jusqu'à ce que le gras plie.")
        XCTAssertEqual(AppLanguageStore.splashTagline, "Nag jusqu'à ce que le gras plie.")
        XCTAssertEqual(AppLanguage.french.splashTagline, "Nag jusqu'à ce que le gras plie.")
        XCTAssertEqual(AppLanguage.english.splashTagline, "Nag until the fat folds.")
        // First-launch path: clearing the key → System → device language tagline.
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppLanguageStore.current, .system)
        XCTAssertEqual(AppLanguageStore.splashTagline, AppLanguage.system.resolved.splashTagline)
        XCTAssertEqual(AppLanguageStore.apply(.french), .french)
        XCTAssertTrue(AppLanguage.french.modelDirective.contains("French"))
        XCTAssertTrue(AppLanguage.french.modelDirective.contains("ZERO"))
        XCTAssertTrue(AppLanguage.french.languageLockFooter.contains("français") || AppLanguage.french.languageLockFooter.contains("FINAL CHECK"))
        XCTAssertTrue(CoachAgentRole.orchestrator.systemPrompt(sex: .male, ageYears: 42).contains("Language lock"))
        XCTAssertTrue(CoachAgentRole.orchestrator.systemPrompt(sex: .male, ageYears: 42).contains("FINAL CHECK"))
        XCTAssertTrue(CoachAgentRole.orchestrator.systemPrompt(sex: .male, ageYears: 42).contains("AGE / GENERATION") || CoachAgentRole.orchestrator.systemPrompt(sex: .male, ageYears: 42).contains("millennial"))
        XCTAssertTrue(AppLanguageStore.locked("Hello").contains("French"))
        XCTAssertTrue(AppLanguageStore.locked("Hello").contains("FINAL CHECK"))
        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first,
            "fr"
        )
        AppLanguageBundleInstaller.installIfNeeded()
        let frBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("fr.lproj", isDirectory: true))
        XCTAssertNotNil(frBundle, "fr.lproj must be in the app after catalog compile")
        XCTAssertEqual(
            frBundle?.localizedString(forKey: "onboarding.cta.continue", value: "?", table: nil),
            "Continuer"
        )
        XCTAssertEqual(
            AppLanguageStore.text("home.mass.reveal", default: "Show weight"),
            "Afficher le poids"
        )
        XCTAssertEqual(
            AppLanguageStore.text("onboarding.cta.continue", default: "Continue"),
            "Continuer"
        )
        XCTAssertEqual(
            AppLanguageStore.text("tab.weigh", default: "Weigh"),
            "Peser"
        )
        XCTAssertEqual(
            AppLanguageStore.text("tab.settings", default: "Settings"),
            "Réglages"
        )
        XCTAssertEqual(
            AppLanguageStore.text("settings.section.you", default: "You"),
            "Toi"
        )
        XCTAssertEqual(
            AppLanguageStore.text("settings.notifications", default: "Notifications"),
            "Notifications"
        )
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "tab.weigh", value: "Weigh", table: nil),
            "Peser"
        )
    }

    func testLegacyKeychainClearIsIdempotent() {
        XCTAssertTrue(GrokLegacyKeychain.clearUserEnteredKey())
        XCTAssertTrue(GrokLegacyKeychain.clearUserEnteredKey())
    }

    func testProjectNearZeroSlopeDoesNotCrash() throws {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 80.01, date: Date(timeIntervalSince1970: day * 7))
        ]
        let projection = try XCTUnwrap(
            HealthChartMath.projectWeightToIdeal(
                windowSamples: samples,
                idealKg: 75,
                now: Date(timeIntervalSince1970: day * 7)
            )
        )
        XCTAssertNotNil(projection.path.last)
    }
}
