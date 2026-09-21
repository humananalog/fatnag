import SwiftUI
import UIKit

/// Profile, notifications, Grok consent, calibration. Live capture uses the weigh-in sheet.
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @FocusState private var focusedField: Field?
    @State private var confirmReset = false
    @State private var notificationAuthLine = "Notifications: checking..."
    @State private var pendingCoachReminders: [PendingCoachReminder] = []
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case reference
        case offset
        case name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileCard
                personaCard
                notificationsCard
                fitnessMonitorCard
                appleIntelligenceCard
                grokCard
                calibrationCard
                privacyCard
                legalCard
            }
            .padding(20)
        }
        .task {
            await refreshNotificationStatus()
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
                Button("Done") { focusedField = nil }
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

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your profile")
                .font(.headline)
            Text("Used on-device for body fat math, greetings, and optional coaching tone.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Name")
                Spacer()
                TextField("Name", text: $session.profile.displayName)
                    .focused($focusedField, equals: .name)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.givenName)
            }

            HStack {
                Text("Height")
                Spacer()
                TextField(
                    "cm",
                    value: $session.profile.heightCm,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("cm").foregroundStyle(.secondary)
            }

            HStack {
                Text("Age")
                Spacer()
                TextField(
                    "years",
                    value: $session.profile.ageYears,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("yr").foregroundStyle(.secondary)
            }

            HStack {
                Text("Target weight")
                Spacer()
                TextField(
                    "kg",
                    value: $session.profile.idealWeightKg,
                    format: .number.precision(.fractionLength(1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("kg").foregroundStyle(.secondary)
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

            HStack {
                Text("Target body fat")
                Spacer()
                TextField(
                    "%",
                    value: Binding(
                        get: { session.profile.idealBodyFatPercent ?? 0 },
                        set: { session.profile.idealBodyFatPercent = $0 > 0.05 ? $0 : nil }
                    ),
                    format: .number.precision(.fractionLength(1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("%").foregroundStyle(.secondary)
            }

            Picker("Sex", selection: $session.profile.sex) {
                ForEach(UserBodyProfile.Sex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            .pickerStyle(.segmented)

            Picker("Diet", selection: $session.profile.dietPreference) {
                ForEach(DietPreference.allCases) { diet in
                    Text(diet.title).tag(diet)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var personaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach persona")
                .font(.headline)
            Text("Location, culture, language, and vibe shape Coach tone. On-device only until you consent to a Grok ask.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Location (e.g. Manila, Hong Kong)", text: $session.profile.location)
            TextField("Ethnicity / culture", text: $session.profile.ethnicity)
            TextField("Preferred language", text: $session.profile.preferredLanguage)
            TextField(
                "Vibe (e.g. Filipina in Manila; French in HK preferring American culture)",
                text: $session.profile.culturalVibe,
                axis: .vertical
            )
            .lineLimit(2...4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notifications", systemImage: "bell.badge")
                .font(.headline)
            Text("Ping only when trends look bad, plus an optional Monday mini-goal nudge. Coach can also schedule one-shot local reminders (wake / timed). On-device Foundation Models can sharpen copy after the schedule lands; they never block delivery. Focus/DND can still silence banners.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(notificationAuthLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    Task {
                        _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
                        await refreshNotificationStatus()
                    }
                } label: {
                    Label("Request permission", systemImage: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openNotificationSettings()
                } label: {
                    Label("System Settings", systemImage: "gear")
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

            Text("Coach reminders")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)

            if pendingCoachReminders.isEmpty {
                Text("No pending Coach reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pendingCoachReminders) { item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                            if let fire = item.nextFire {
                                Text(fire.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.body)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var fitnessMonitorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Health ↔ Grok monitoring", systemImage: "heart.text.square")
                .font(.headline)
            Text("Reads HR, RHR, HRV (SDNN), respiratory rate, wrist temperature, SpO2, VO2 max, sleep (stages when available), steps, active energy, Exercise Time, walking/running distance, and workouts from Apple Health (after permission). Coach refreshes this dated digest on every ask. Third-party apps (AllTrails, Strava, etc.) only appear after they write into Apple Health. The Scale never reads those apps directly. iOS background is best-effort; local notifications nudge you to open the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Health status")
                .font(.caption.weight(.semibold))
            Text(session.healthAccessStatusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    Task { await session.requestHealthAccessFromSettings() }
                } label: {
                    Label("Allow Health access", systemImage: "heart.text.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openAppleHealth()
                } label: {
                    Label("Open Health", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Toggle(
                "Enable fitness monitoring",
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
                "Notify on bad Watch / sleep-HR signals",
                isOn: Binding(
                    get: { session.fitnessMonitorPreferences.notifyOnTriggers },
                    set: {
                        var next = session.fitnessMonitorPreferences
                        next.notifyOnTriggers = $0
                        session.fitnessMonitorPreferences = next
                    }
                )
            )

            HStack {
                Text("Pre-sleep HR window")
                Spacer()
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
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                Text("min").foregroundStyle(.secondary)
            }
            .font(.footnote)

            HStack {
                Text("Flag if pre-sleep HR ≥")
                Spacer()
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
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                Text("bpm").foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            if !session.lastFitnessTriggers.isEmpty {
                Text(session.lastFitnessTriggers.map(\.message).joined(separator: "\n"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            _ = await session.refreshFitnessDigestForCoach()
        }
    }

    private func openAppleHealth() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
    }

    private var appleIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple Intelligence", systemImage: "brain.head.profile")
                .font(.headline)
            Text("On-device Foundation Models polish notification copy, help decide whether a ping is worth it, and summarize private Health digests when Grok is offline. Nothing leaves the phone for these.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(FoundationModelAvailability.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Hybrid: FM for private snippets + notification judgment. Grok Worker for full multi-agent Coach when online and consented.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var grokCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Grok coach", systemImage: "sparkles")
                .font(.headline)
            Text("Shared for every install of this build. You never paste an API key here. Coach sends only a short trend / chat / fitness digest after consent. If the proxy URL is broken, you'll see a clear error (not a fake offline roast).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "Allow Grok coach requests",
                isOn: Binding(
                    get: { GrokPrivacyConsent.isAccepted },
                    set: { GrokPrivacyConsent.isAccepted = $0 }
                )
            )

            Text(GrokSharedConfig.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                GrokSharedConfig.isLiveConfigured
                    ? "Live Grok ready when consent is on."
                    : "Offline mock until the operator sets GROK_PROXY_URL in TheScale.xcconfig and rebuilds."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weight calibration", systemImage: "slider.horizontal.3")
                .font(.headline)

            Text("Enter the true mass, open the live sheet, weigh it, then store. Same screen as a normal weigh-in.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. True mass (reference)")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Text("Known mass")
                    Spacer()
                    TextField(
                        "kg",
                        value: Binding(
                            get: { session.calibration.referenceMassKg },
                            set: { session.updateCalibrationReferenceMass($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .reference)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    Text("kg").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("2. Capture mode")
                    .font(.subheadline.weight(.semibold))
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
                    .foregroundStyle(.secondary)
            }

            Button {
                focusedField = nil
                session.beginCalibrationWeighIn()
                dismiss()
            } label: {
                Label("Weigh reference on live sheet", systemImage: "scalemass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                focusedField = nil
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

            VStack(alignment: .leading, spacing: 6) {
                Text("3. Current correction")
                    .font(.subheadline.weight(.semibold))
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

                HStack {
                    Text("Manual offset (kg)")
                    Spacer()
                    TextField(
                        "offset",
                        value: Binding(
                            get: { session.calibration.offsetKg },
                            set: { session.updateCalibrationOffset($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .offset)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                }
                .font(.footnote)
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset calibration", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy & Health", systemImage: "lock.shield")
                .font(.headline)
            Text("Profile, calibration, memory, persona, and readings stay on this iPhone. Health is read for trend, history, and optional fitness monitoring (HR, sleep, steps, energy, workouts), and written only after you confirm a weigh-in. On-device Apple Intelligence (when available) polishes notifications and private digests without leaving the phone. Grok is opt-in after consent. The shared xAI key lives on the operator's Worker (or a build-time secret), never in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("If permissions were denied: Settings → Health → Data Access → The Scale. Notifications: Settings → Notifications → The Scale. Apple Intelligence: Settings → Apple Intelligence & Siri.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Legal", systemImage: "doc.text")
                .font(.headline)
            Text(CoachCopySanitize.medicalDisclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Shown once during onboarding. Coach chat does not repeat this.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Discreet Dev affordance: force Monday weekly card without Monday morning weigh-in.
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
            } label: {
                Text("Dev")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Developer Monday card tools")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeHelpText: String {
        switch session.calibration.captureMode {
        case .offset:
            return "Offset: corrected = raw + (true - raw). Good for a small constant bias (e.g. 7.90 vs 7.926)."
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
