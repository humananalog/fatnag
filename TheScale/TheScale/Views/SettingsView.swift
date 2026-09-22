import SwiftUI
import UIKit

/// Profile, AI usage, Coach, Health, calibration, legal.
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var subscription = ScaleSubscriptionStore.shared
    @FocusState private var focusedField: Field?
    @State private var confirmReset = false
    @State private var notificationAuthLine = "Notifications: checking..."
    @State private var pendingCoachReminders: [PendingCoachReminder] = []
    @State private var healthBackgroundLine = "Health background: checking..."
    @State private var samplePingNote: String?
    @State private var showPaywall = false
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case name, height, age, targetWeight, bodyFat
        case location, ethnicity, language, vibe, avoidances
        case reference, offset
        case preSleepWindow, preSleepHR
    }

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.35, green: 0.37, blue: 0.40)
    private let accent = Color(red: 0.18, green: 0.52, blue: 0.62)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                sectionLabel("You")
                profileCard

                sectionLabel("Weekly AI")
                planCard

                sectionLabel("Coach")
                coachCard

                sectionLabel("Alerts & Health")
                notificationsCard
                fitnessMonitorCard

                sectionLabel("Scale")
                calibrationCard

                sectionLabel("Privacy & Legal")
                privacyCard
                legalCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .task {
            await refreshNotificationStatus()
            await subscription.refresh()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                lockMessage: nil,
                highlighted: subscription.plan.upgradeTarget ?? .plus
            )
            .environmentObject(session)
            .presentationDragIndicator(.visible)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.88, green: 0.91, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .fontWeight(.semibold)
            }
        }
        .alert("Reset calibration?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                session.resetCalibration()
            }
        } message: {
            Text("Removes the stored scale factor and offset. Your reference mass value is kept.")
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(steel)
            .tracking(0.8)
            .padding(.bottom, -12)
    }

    private func settingsPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Weekly AI

    private var planCard: some View {
        let snap = subscription.quotaSnapshot
        return settingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Online AI usage", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Live Keel for chat, Monday card, fitness checks, and meal plans. On-device Coach stays unlimited. Resets Monday.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                HStack(alignment: .firstTextBaseline) {
                    Text(subscription.plan.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(subscription.plan.priceLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(steel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(snap.percentLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Spacer()
                        Text("\(snap.percentUsed)%")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(snap.isExhausted ? Color.orange : ink)
                    }
                    ProgressView(value: Double(snap.percentUsed), total: 100)
                        .tint(snap.isExhausted ? .orange : accent)
                    HStack {
                        Text(snap.usageCountLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(steel)
                        Spacer()
                        Text("\(snap.remaining) left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(snap.isExhausted ? .orange : steel)
                    }
                }
                .padding(12)
                .background(
                    (snap.isExhausted ? Color.orange.opacity(0.10) : accent.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

                if let target = subscription.plan.upgradeTarget {
                    Button {
                        dismissKeyboard()
                        showPaywall = true
                    } label: {
                        Label(
                            snap.isExhausted
                                ? "Upgrade to \(target.displayName)"
                                : "Upgrade to \(target.displayName) · \(target.weeklyGrokCredits)/wk",
                            systemImage: "arrow.up.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(snap.isExhausted ? .orange : accent)
                } else {
                    Button {
                        dismissKeyboard()
                        showPaywall = true
                    } label: {
                        Label("Manage plans", systemImage: "creditcard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text(subscription.commerceStatusLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.commerceStatus")

                #if DEBUG
                Text("DEBUG commerce")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(steel)
                Text(subscription.commerceLane.detail)
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    subscription.useRealStoreKit()
                } label: {
                    Label("Use StoreKit (Human Analog)", systemImage: "cart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .accessibilityIdentifier("settings.useStoreKit")

                Picker(
                    "DEBUG plan override",
                    selection: Binding(
                        get: { subscription.debugOverride?.rawValue ?? "storekit" },
                        set: { raw in
                            if raw == "storekit" {
                                subscription.useRealStoreKit()
                            } else if let plan = ScalePlan(rawValue: raw) {
                                subscription.debugOverride = plan
                            }
                        }
                    )
                ) {
                    Text("StoreKit").tag("storekit")
                    ForEach(ScalePlan.allCases) { plan in
                        Text(plan.displayName).tag(plan.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.debugPlanOverride")

                Button("Reload StoreKit products") {
                    Task { await subscription.refresh() }
                }
                .font(.caption)
                .accessibilityIdentifier("settings.reloadProducts")

                Button("DEBUG reset weekly quota") {
                    CoachWeeklyQuota.debugReset()
                    subscription.noteQuotaChange()
                }
                .font(.caption)
                #endif
            }
        }
        .id(subscription.quotaEpoch)
    }

    // MARK: - You

    private var profileCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("On-device for body fat, greetings, and Coach tone.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                fieldRow("Name") {
                    TextField("Name", text: $session.profile.displayName)
                        .focused($focusedField, equals: .name)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.givenName)
                }

                Picker("Units", selection: $session.preferredUnits) {
                    ForEach(PreferredUnitSystem.allCases) { system in
                        Text(system.shortTitle).tag(system)
                    }
                }
                .pickerStyle(.segmented)

                Text("Weight, height, portions, meal plan, and Coach use this. Health stays metric under the hood.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                fieldRow("Height") {
                    TextField(
                        session.preferredUnits.heightLabel,
                        value: Binding(
                            get: {
                                UnitFormat.height(fromCm: session.profile.heightCm, system: session.preferredUnits)
                            },
                            set: { display in
                                session.profile.heightCm = UnitFormat.cm(fromHeight: display, system: session.preferredUnits)
                            }
                        ),
                        format: .number.precision(.fractionLength(session.preferredUnits == .metric ? 0 : 1))
                    )
                    .focused($focusedField, equals: .height)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    Text(session.preferredUnits.heightLabel).foregroundStyle(steel)
                }

                fieldRow("Age") {
                    TextField(
                        "years",
                        value: Binding(
                            get: { session.profile.ageYears },
                            set: { raw in
                                let clamped = min(UserBodyProfile.maximumAgeYears, max(UserBodyProfile.minimumAgeYears, raw.rounded()))
                                session.profile.ageYears = clamped
                            }
                        ),
                        format: .number.precision(.fractionLength(0))
                    )
                    .focused($focusedField, equals: .age)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    Text("yr").foregroundStyle(steel)
                }
                Text("18 or older.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                fieldRow("Target weight") {
                    TextField(
                        session.preferredUnits.massLabel,
                        value: Binding(
                            get: {
                                UnitFormat.mass(fromKg: session.profile.idealWeightKg, system: session.preferredUnits)
                            },
                            set: { display in
                                session.profile.idealWeightKg = UnitFormat.kg(fromMass: display, system: session.preferredUnits)
                            }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .focused($focusedField, equals: .targetWeight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    Text(session.preferredUnits.massLabel).foregroundStyle(steel)
                }

                fieldRow("Target body fat") {
                    TextField(
                        "%",
                        value: Binding(
                            get: { session.profile.idealBodyFatPercent ?? 0 },
                            set: { session.profile.idealBodyFatPercent = $0 > 0.05 ? $0 : nil }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .focused($focusedField, equals: .bodyFat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    Text("%").foregroundStyle(steel)
                }

                DatePicker(
                    "Goal date",
                    selection: Binding(
                        get: { session.profile.goalDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())! },
                        set: { session.profile.goalDate = $0 }
                    ),
                    displayedComponents: .date
                )
                Toggle(
                    "Use goal date for Monday pacing",
                    isOn: Binding(
                        get: { session.profile.goalDate != nil },
                        set: { on in
                            if on {
                                if session.profile.goalDate == nil {
                                    session.profile.goalDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())
                                }
                            } else {
                                session.profile.goalDate = nil
                            }
                        }
                    )
                )
                .font(.footnote)

                Picker("Gender", selection: $session.profile.sex) {
                    ForEach(UserBodyProfile.Sex.allCases) { sex in
                        Text(sex.title).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.gender")

                Picker("Diet", selection: Binding(
                    get: { session.profile.dietPreference },
                    set: {
                        session.profile.dietPreference = $0
                        session.profile.dietPreferenceConfirmed = true
                        session.clearMealPlanCache()
                    }
                )) {
                    ForEach(DietPreference.allCases) { diet in
                        Text(diet.title).tag(diet)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.diet")
            }
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(ink)
            Spacer()
            content()
        }
    }

    // MARK: - Coach

    private var coachCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Persona & AI")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Tone stays on-device until you consent to a live Keel ask.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                TextField("Location (e.g. Manila, Hong Kong)", text: $session.profile.location)
                    .focused($focusedField, equals: .location)
                Toggle(isOn: $session.profile.useLocalContext) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use for local food and fitness")
                            .font(.footnote.weight(.semibold))
                        Text("Markets, meal staples, and nearby fitness when on.")
                            .font(.caption2)
                            .foregroundStyle(steel)
                    }
                }
                .accessibilityIdentifier("settings.useLocalContext")
                TextField(
                    "Avoid (allergies, hard nos)",
                    text: Binding(
                        get: { session.profile.foodAvoidances },
                        set: {
                            session.profile.foodAvoidances = $0
                            session.profile.foodAvoidancesConfirmed = true
                        }
                    ),
                    axis: .vertical
                )
                .focused($focusedField, equals: .avoidances)
                .lineLimit(2...4)
                .accessibilityIdentifier("settings.foodAvoidances")
                TextField("Ethnicity / culture", text: $session.profile.ethnicity)
                    .focused($focusedField, equals: .ethnicity)
                TextField("Preferred language", text: $session.profile.preferredLanguage)
                    .focused($focusedField, equals: .language)
                TextField(
                    "Vibe (short coach-facing note)",
                    text: $session.profile.culturalVibe,
                    axis: .vertical
                )
                .focused($focusedField, equals: .vibe)
                .lineLimit(2...4)

                Divider().padding(.vertical, 4)

                Toggle(
                    CoachPersona.consentToggleTitle,
                    isOn: Binding(
                        get: { GrokPrivacyConsent.isAccepted },
                        set: { GrokPrivacyConsent.isAccepted = $0 }
                    )
                )
                Text(GrokSharedConfig.statusSummary)
                    .font(.caption)
                    .foregroundStyle(steel)

                Text(FoundationModelAvailability.statusSummary)
                    .font(.caption)
                    .foregroundStyle(steel)
                Text("Apple Intelligence polishes private copy on-device. Keel handles live multi-agent Coach when consented.")
                    .font(.caption2)
                    .foregroundStyle(steel)
            }
        }
    }

    // MARK: - Alerts

    private var notificationsCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Notifications", systemImage: "bell.badge")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Local banners with actions. Focus/DND can still silence them.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                Text(notificationAuthLine)
                    .font(.caption)
                    .foregroundStyle(steel)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
                            await refreshNotificationStatus()
                        }
                    } label: {
                        Label("Allow", systemImage: "bell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("System", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle(
                    "Bad-trend alerts",
                    isOn: Binding(
                        get: { session.notificationPreferences.notifyOnBadTrend },
                        set: {
                            var next = session.notificationPreferences
                            next.notifyOnBadTrend = $0
                            session.notificationPreferences = next
                            Task { await session.refreshTrendNotifications() }
                        }
                    )
                )
                Toggle(
                    "Weekly mini-goal reminder",
                    isOn: Binding(
                        get: { session.notificationPreferences.weeklyGoalReminders },
                        set: {
                            var next = session.notificationPreferences
                            next.weeklyGoalReminders = $0
                            session.notificationPreferences = next
                            Task { await session.refreshTrendNotifications() }
                        }
                    )
                )

                if !pendingCoachReminders.isEmpty {
                    Text("Pending Coach reminders")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 4)
                    ForEach(pendingCoachReminders) { item in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                if let fire = item.nextFire {
                                    Text(fire.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(steel)
                                }
                            }
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                CoachReminderScheduler.cancelCoachReminder(id: item.id)
                                Task { await refreshNotificationStatus() }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                    Button("Cancel all Coach reminders") {
                        Task {
                            await CoachReminderScheduler.cancelAllCoachReminders()
                            await refreshNotificationStatus()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationAuthLine = await CoachReminderScheduler.authorizationStatusLine()
        pendingCoachReminders = await CoachReminderScheduler.listPendingCoachReminders()
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Health

    private var fitnessMonitorCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple Health", systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Coach reads HealthKit after permission. Third-party apps only appear if they write to Health.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                Text(session.healthAccessStatusLine)
                    .font(.caption)
                    .foregroundStyle(steel)
                Text(healthBackgroundLine)
                    .font(.caption2)
                    .foregroundStyle(steel)

                HStack(spacing: 8) {
                    Button {
                        Task { await session.requestHealthAccessFromSettings() }
                    } label: {
                        Label("Allow Health", systemImage: "heart.text.square.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button {
                        openAppleHealth()
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle(
                    "Fitness monitoring",
                    isOn: Binding(
                        get: { session.fitnessMonitorPreferences.enabled },
                        set: {
                            var next = session.fitnessMonitorPreferences
                            next.enabled = $0
                            session.fitnessMonitorPreferences = next
                            if $0 {
                                Task { _ = await session.runFitnessMonitorCheck(force: true) }
                            }
                        }
                    )
                )

                Picker(
                    "Check interval",
                    selection: Binding(
                        get: { session.fitnessMonitorPreferences.interval },
                        set: {
                            var next = session.fitnessMonitorPreferences
                            next.interval = $0
                            session.fitnessMonitorPreferences = next
                        }
                    )
                ) {
                    ForEach(GrokCheckInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.menu)

                Toggle(
                    "Notify on Watch / sleep-HR signals",
                    isOn: Binding(
                        get: { session.fitnessMonitorPreferences.notifyOnTriggers },
                        set: {
                            var next = session.fitnessMonitorPreferences
                            next.notifyOnTriggers = $0
                            session.fitnessMonitorPreferences = next
                        }
                    )
                )

                fieldRow("Pre-sleep HR window") {
                    TextField(
                        "min",
                        value: Binding(
                            get: { session.fitnessMonitorPreferences.thresholds.preSleepHRWindowMinutes },
                            set: {
                                var next = session.fitnessMonitorPreferences
                                next.thresholds.preSleepHRWindowMinutes = max(10, min($0, 90))
                                session.fitnessMonitorPreferences = next
                            }
                        ),
                        format: .number
                    )
                    .focused($focusedField, equals: .preSleepWindow)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    Text("min").foregroundStyle(steel)
                }
                .font(.footnote)

                fieldRow("Flag if pre-sleep HR ≥") {
                    TextField(
                        "bpm",
                        value: Binding(
                            get: { session.fitnessMonitorPreferences.thresholds.preSleepHRAbsoluteBpm },
                            set: {
                                var next = session.fitnessMonitorPreferences
                                next.thresholds.preSleepHRAbsoluteBpm = max(60, min($0, 140))
                                session.fitnessMonitorPreferences = next
                            }
                        ),
                        format: .number.precision(.fractionLength(0))
                    )
                    .focused($focusedField, equals: .preSleepHR)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    Text("bpm").foregroundStyle(steel)
                }
                .font(.footnote)

                Button {
                    Task { _ = await session.runFitnessMonitorCheck(force: true) }
                } label: {
                    Label("Run check now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let reply = session.lastFitnessCoachReply {
                    Text("Last Coach note")
                        .font(.caption.weight(.semibold))
                    Text(reply)
                        .font(.caption)
                        .foregroundStyle(steel)
                }
                if !session.lastFitnessTriggers.isEmpty {
                    Text(session.lastFitnessTriggers.map(\.message).joined(separator: "\n"))
                        .font(.caption2)
                        .foregroundStyle(steel)
                }
            }
        }
        .task {
            _ = await session.refreshFitnessDigestForCoach()
            healthBackgroundLine = HealthKitBackgroundDelivery.shared.statusLine()
        }
    }

    private func openAppleHealth() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
    }

    // MARK: - Scale

    private var calibrationCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Weight calibration", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Enter true mass, open the live sheet, weigh, then store.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                fieldRow("Known mass") {
                    TextField(
                        "kg",
                        value: Binding(
                            get: { session.calibration.referenceMassKg },
                            set: { session.updateCalibrationReferenceMass($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .focused($focusedField, equals: .reference)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    Text("kg").foregroundStyle(steel)
                }

                Picker(
                    "Mode",
                    selection: Binding(
                        get: { session.calibration.captureMode },
                        set: { session.setCalibrationCaptureMode($0) }
                    )
                ) {
                    ForEach(ScaleCalibration.CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(modeHelpText)
                    .font(.caption2)
                    .foregroundStyle(steel)

                Button {
                    dismissKeyboard()
                    session.beginCalibrationWeighIn()
                    dismiss()
                } label: {
                    Label("Weigh reference on live sheet", systemImage: "scalemass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {
                    dismissKeyboard()
                    _ = session.recordCalibration(
                        referenceKg: 7.926,
                        rawKg: 7.90,
                        mode: .offset
                    )
                } label: {
                    Label("Store Alex's 7.926 / 7.90 offset", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(session.calibration.summaryLine)
                    .font(.footnote.weight(.medium))
                Toggle(
                    "Apply correction",
                    isOn: Binding(
                        get: { session.calibration.isActive },
                        set: { session.setCalibrationActive($0) }
                    )
                )
                .disabled(!session.calibration.hasCorrection && !session.calibration.isActive)

                fieldRow("Manual offset (kg)") {
                    TextField(
                        "offset",
                        value: Binding(
                            get: { session.calibration.offsetKg },
                            set: { session.updateCalibrationOffset($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .focused($focusedField, equals: .offset)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                }
                .font(.footnote)

                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Reset calibration", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Privacy & Legal

    private var privacyCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Privacy", systemImage: "lock.shield")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Profile, calibration, memory, and readings stay on this iPhone. Health is read/written only with permission. Keel is opt-in. Apple Intelligence stays on-device.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy Policy", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Link(destination: ScaleLegal.privacyPolicyURL) {
                    Label("Privacy Policy (web)", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Legal", systemImage: "doc.text")
                .font(.headline)
                .foregroundStyle(ink)
            Text(CoachCopySanitize.medicalDisclaimer)
                .font(.caption)
                .foregroundStyle(steel)
            Text("Shown once during onboarding. Coach chat and notifications do not repeat this.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            #if DEBUG
            Menu {
                Button("Preview Monday card") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        session.forcePresentMondayCard(regenerate: false)
                    }
                }
                Button("Regenerate Monday card") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        session.forcePresentMondayCard(regenerate: true)
                    }
                }
                Button("Fire sample SOTA notification") {
                    Task {
                        let ok = await GrokFitnessMonitor.fireSampleSOTANotification(
                            profileName: session.profile.greetingName,
                            currentKg: session.healthBaselineKg
                        )
                        samplePingNote = ok
                            ? "Sample ping scheduled (~1.5s). Lock phone or leave app."
                            : "Sample ping failed. Allow notifications first."
                        await refreshNotificationStatus()
                    }
                }
                Button("Force soft review prompt") {
                    ScaleAppReviewPrompt.successfulWeighIns = max(
                        ScaleAppReviewPrompt.successfulWeighIns,
                        ScaleAppReviewPrompt.minimumWeighIns
                    )
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        session.isAppReviewPromptPresented = true
                    }
                }
                Button("Reset review prompt state") {
                    ScaleAppReviewPrompt.debugReset()
                    samplePingNote = "Review prompt state cleared."
                }
                Button("Reset onboarding (relaunch flow)") {
                    OnboardingStore.hasCompleted = false
                    session.hasCompletedOnboarding = false
                    dismiss()
                }
            } label: {
                Text("Dev")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Developer tools")

            if let samplePingNote {
                Text(samplePingNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeHelpText: String {
        switch session.calibration.captureMode {
        case .offset:
            return "Offset: corrected = raw + (true - raw). Good for a small constant bias."
        case .factor:
            return "Factor: corrected = raw × (true / raw). Better when error grows with mass."
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ScaleSessionViewModel())
    }
}
