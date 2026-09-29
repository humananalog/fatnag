import SwiftUI
import UIKit
import ScaleOnDevicePolish

/// Profile, AI usage, Coach, Health, calibration, legal — consumer Settings (App Review clean).
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var subscription = ScaleSubscriptionStore.shared
    @ObservedObject private var onDevicePolish = OnDevicePolishInstaller.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var confirmReset = false
    @State private var notificationAuthLine = "Notifications: checking..."
    @State private var notificationAuthDenied = false
    @State private var pendingCoachReminders: [PendingCoachReminder] = []
    @State private var healthBackgroundLine = "Health background: checking..."
    @State private var heightValidationNote: String?
    @State private var ageValidationNote: String?
    @State private var weightValidationNote: String?
    @State private var bodyFatValidationNote: String?
    @State private var bodyFatText: String = ""
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var exportShareURL: URL?
    @State private var showEraseConfirm = false
    @State private var dataRightsNote: String?
    @State private var languageValidationNote: String?
    @State private var languageRejected = false
    /// Draft age on the wheel before Confirm.
    @State private var draftAgeYears: Int = 30
    @State private var pendingHeightCm: Double?
    @State private var pendingAgeYears: Double?
    @State private var pendingIdealKg: Double?
    @State private var pendingSex: UserBodyProfile.Sex?
    @State private var confirmHeightChange = false
    @State private var confirmAgeChange = false
    @State private var confirmDreamWeightChange = false
    @State private var confirmSexChange = false
    @State private var draftHeightDisplay: Double = 170
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case name, height, age, bodyFat
        case location, ethnicity, language, vibe, avoidances, healthContext
        case reference, offset
        case preSleepWindow, preSleepHR
    }

    private var dreamBoundsKg: ClosedRange<Double> {
        GoalPaceGuard.dreamWeightBoundsKg(
            currentKg: session.healthBaselineKg
                ?? session.profile.startingWeightKg
                ?? session.profile.idealWeightKg,
            heightCm: session.profile.heightCm,
            sex: session.profile.sex,
            ageYears: session.profile.ageYears
        )
    }

    private var universe: ScalePaletteUniverse {
        ScalePaletteUniverse.resolve(sex: session.profile.sex)
    }

    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.95, blue: 0.92)
            : Color(red: 0.08, green: 0.09, blue: 0.11)
    }

    private var steel: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.74, blue: 0.78)
            : Color(red: 0.32, green: 0.34, blue: 0.38)
    }

    private var accent: Color {
        ScaleChrome.signal(for: universe)
    }

    private var copper: Color {
        ScaleChrome.ember(for: universe)
    }

    private var panelFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.82)
    }

    private var softPanelFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.58)
    }

    private var appMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                brandHeader

                sectionLabel(String(localized: "settings.section.language", defaultValue: "Language"))
                languageCard

                sectionLabel(String(localized: "settings.section.you", defaultValue: "You"))
                profileCard

                sectionLabel(String(localized: "settings.section.weekly_ai", defaultValue: "Weekly AI"))
                planCard

                sectionLabel(String(localized: "settings.section.coach", defaultValue: "Coach"))
                coachCard

                sectionLabel(String(localized: "settings.section.alerts_health", defaultValue: "Alerts & Health"))
                notificationsCard
                fitnessMonitorCard

                sectionLabel(String(localized: "settings.section.scale", defaultValue: "Scale"))
                calibrationCard

                sectionLabel(String(localized: "settings.section.privacy_legal", defaultValue: "Privacy & Legal"))
                privacyCard
                legalCard

                sectionLabel(String(localized: "settings.section.help", defaultValue: "Help"))
                feedbackCard

                sectionLabel(String(localized: "settings.section.app", defaultValue: "App"))
                aboutCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .task {
            syncBodyFatTextFromProfile()
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
        .sheet(isPresented: $showFeedback) {
            FeedbackSheetView(
                source: .settings,
                planTier: subscription.plan.rawValue
            )
        }
        .scrollDismissesKeyboard(.interactively)
        .background(settingsBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "common.done", defaultValue: "Done")) { dismissKeyboard() }
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
        .alert("Confirm height change?", isPresented: $confirmHeightChange) {
            Button("No", role: .cancel) {
                pendingHeightCm = nil
                syncDraftHeightFromProfile()
            }
            Button("Yes") { applyPendingHeight() }
        } message: {
            if let cm = pendingHeightCm {
                Text(
                    "Update height to \(UnitFormat.heightString(cm, system: session.preferredUnits, fractionDigits: session.preferredUnits == .metric ? 0 : 1))? BMI, dream weight band, and body-fat math will refresh."
                )
            }
        }
        .alert("Confirm age change?", isPresented: $confirmAgeChange) {
            Button("No", role: .cancel) {
                pendingAgeYears = nil
                draftAgeYears = Int(session.profile.ageYears.rounded())
            }
            Button("Yes") { applyPendingAge() }
        } message: {
            if let age = pendingAgeYears {
                Text("Update age to \(Int(age.rounded())) years? Dream targets and suggested body fat will refresh.")
            }
        }
        .alert("Confirm dream weight?", isPresented: $confirmDreamWeightChange) {
            Button("No", role: .cancel) {
                pendingIdealKg = nil
            }
            Button("Yes") { applyPendingDreamWeight() }
        } message: {
            if let kg = pendingIdealKg {
                Text(
                    "Set dream weight to \(UnitFormat.massString(kg, system: session.preferredUnits, fractionDigits: 1))?"
                )
            }
        }
        .alert(
            "Changing gender is a painful process, are you sure you want to do that?",
            isPresented: $confirmSexChange
        ) {
            Button("No", role: .cancel) { pendingSex = nil }
            Button("Yes") { applyPendingSex() }
        } message: {
            Text("Targets and body-composition formulas will recalibrate for the new gender. Not the same variables for women and men.")
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

    private var settingsBackground: some View {
        let dayTop: Color
        let dayBottom: Color
        let nightTop: Color
        let nightBottom: Color
        switch universe {
        case .glacierForge:
            dayTop = Color(red: 0.93, green: 0.96, blue: 0.98)
            dayBottom = Color(red: 0.86, green: 0.91, blue: 0.95)
            nightTop = Color(red: 0.06, green: 0.09, blue: 0.13)
            nightBottom = Color(red: 0.05, green: 0.07, blue: 0.11)
        case .bloomCopper:
            dayTop = Color(red: 0.98, green: 0.94, blue: 0.93)
            dayBottom = Color(red: 0.95, green: 0.88, blue: 0.86)
            nightTop = Color(red: 0.10, green: 0.07, blue: 0.09)
            nightBottom = Color(red: 0.08, green: 0.05, blue: 0.07)
        }
        return LinearGradient(
            colors: colorScheme == .dark ? [nightTop, nightBottom] : [dayTop, dayBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var languageCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "settings.language", defaultValue: "App language"), systemImage: "globe")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.language.help",
                    defaultValue: "Sets the app UI, the splash line, and Keel. On-device models use the same language."
                ))
                .font(.footnote)
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)

                Picker(
                    String(localized: "settings.language", defaultValue: "App language"),
                    selection: Binding(
                        get: { AppLanguageStore.current },
                        set: { lang in
                            guard let applied = AppLanguageStore.apply(lang) else {
                                languageRejected = true
                                languageValidationNote = String(
                                    localized: "settings.language.invalid",
                                    defaultValue: "That language is not available."
                                )
                                return
                            }
                            languageRejected = false
                            session.profile.preferredLanguage = applied.resolved.profileLanguageName
                            languageValidationNote = String(
                                localized: "settings.language.applied",
                                defaultValue: "UI and Keel now use \(applied.nativeLabel)."
                            )
                        }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativeLabel).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.appLanguage")

                Text(AppLanguageStore.current.resolved.splashTagline)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("settings.language.tagline")

                if let languageValidationNote {
                    Text(languageValidationNote)
                        .font(.caption)
                        .foregroundStyle(languageRejected ? Color.orange : steel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.language.validation")
                }
            }
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            FatnagWordmark(size: 28, color: ink)
                .accessibilityIdentifier("settings.brand")
            Text(FatnagBrand.tagline)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(copper)
            Text(String(
                localized: "settings.brand.blurb",
                defaultValue: "Profile, Coach, Health, and privacy — all on this iPhone."
            ))
                .font(.footnote)
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(steel)
            .tracking(1.0)
            .padding(.bottom, -12)
            .accessibilityAddTraits(.isHeader)
    }

    private func settingsPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ink.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
            )
    }

    // MARK: - Weekly AI

    private var planCard: some View {
        let snap = subscription.quotaSnapshot
        return settingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "settings.ai.usage", defaultValue: "Online AI usage"), systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.ai.usage.help",
                    defaultValue: "Live Keel for chat, Monday card, fitness checks, and meal plans. On-device Coach stays unlimited. Resets Monday."
                ))
                    .font(.footnote)
                    .foregroundStyle(steel)

                HStack(alignment: .firstTextBaseline) {
                    Text(subscription.plan.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(subscription.priceLabel(for: subscription.plan))
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
                    ScaleBoundedProgress(
                        value: Double(snap.percentUsed),
                        total: 100,
                        tint: snap.isExhausted ? .orange : accent,
                        track: ink.opacity(0.12),
                        height: 6
                    )
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

                Button {
                    Task { await subscription.restore() }
                } label: {
                    Label {
                        Text(subscription.isRestoring
                              ? String(localized: "paywall.restoring", defaultValue: "Restoring…")
                              : String(localized: "paywall.restore", defaultValue: "Restore purchases"))
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(subscription.isRestoring)
                .accessibilityIdentifier("settings.restorePurchases")

                if let restore = subscription.restoreMessage {
                    Text(restore)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.restoreMessage")
                }
                if let err = subscription.purchaseError {
                    Text(err)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Subscriptions via Apple. Restore if you already bought Plus or Pro on this Apple ID.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.commerceStatus")
            }
        }
        .id(subscription.quotaEpoch)
    }

    // MARK: - App

    private var aboutCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("App details", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(ink)
                HStack(alignment: .firstTextBaseline) {
                    FatnagWordmark(size: 20, color: ink)
                    Spacer()
                    Text("v\(appMarketingVersion)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(copper)
                        .accessibilityIdentifier("settings.appVersion")
                }
                Text("Build \(appBuildVersion) · Human Analog Limited")
                    .font(.caption)
                    .foregroundStyle(steel)
                    .accessibilityIdentifier("settings.appBuild")
                Text(universe.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("settings.paletteUniverse")
            }
        }
    }

    // MARK: - You

    private var profileCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "settings.profile", defaultValue: "Profile"))
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.profile.help",
                    defaultValue: "On-device for body fat estimates, greetings, and Coach tone."
                ))
                    .font(.footnote)
                    .foregroundStyle(steel)

                labeledField(
                    title: "Name",
                    help: "What Keel calls you in drills and chat."
                ) {
                    TextField("Your first name", text: $session.profile.displayName)
                        .focused($focusedField, equals: .name)
                        .textContentType(.givenName)
                }

                Text(String(localized: "settings.units", defaultValue: "Units"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Picker(String(localized: "settings.units", defaultValue: "Units"), selection: $session.preferredUnits) {
                    ForEach(PreferredUnitSystem.allCases) { system in
                        Text(system.shortTitle).tag(system)
                    }
                }
                .pickerStyle(.segmented)
                Text(String(
                    localized: "settings.units.help",
                    defaultValue: "Weight, height, portions, meal plan, and Coach use this. Health stays metric under the hood."
                ))
                    .font(.caption2)
                    .foregroundStyle(steel)

                labeledField(
                    title: "Height",
                    help: "Used for BMI and body-fat math. Changing asks for confirmation. About 120-250 cm / 3'11\"-8'2\"."
                ) {
                    HStack(spacing: 6) {
                        TextField(
                            session.preferredUnits.heightLabel,
                            value: $draftHeightDisplay,
                            format: .number.precision(.fractionLength(session.preferredUnits == .metric ? 0 : 1))
                        )
                        .focused($focusedField, equals: .height)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 64)
                        .onChange(of: focusedField) { _, field in
                            if field != .height {
                                proposeHeightFromDraft()
                            }
                        }
                        Text(session.preferredUnits.heightLabel)
                            .foregroundStyle(steel)
                        Button("Apply") { proposeHeightFromDraft() }
                            .font(.caption.weight(.semibold))
                    }
                }
                if let heightValidationNote {
                    validationLine(heightValidationNote)
                }

                labeledField(
                    title: "Age",
                    help: "Adults only. Apple wheel selector. Changing asks for confirmation."
                ) {
                    VStack(spacing: 8) {
                        Picker("Age", selection: $draftAgeYears) {
                            ForEach(Int(UserBodyProfile.minimumAgeYears)...Int(UserBodyProfile.maximumAgeYears), id: \.self) { year in
                                Text("\(year) years").tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 120)
                        .accessibilityIdentifier("settings.age.wheel")
                        Button("Apply age") {
                            proposeAgeFromDraft()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
                if let ageValidationNote {
                    validationLine(ageValidationNote)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.dream_weight", defaultValue: "Dream / target weight"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(
                        String(
                            localized: "settings.dream_weight.help",
                            defaultValue: "Drag the scale, then confirm. Range is BMI-safe for your height, sex, and age. Markers follow metric or imperial Units."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)

                    AnalogDreamScaleView(
                        weightKg: Binding(
                            get: { pendingIdealKg ?? session.profile.idealWeightKg },
                            set: { next in
                                pendingIdealKg = next
                            }
                        ),
                        boundsKg: dreamBoundsKg,
                        unitSystem: session.preferredUnits,
                        ink: ink,
                        steel: steel,
                        accent: accent,
                        accessibilityId: "settings.targetWeight.analog",
                        caption: String(
                            localized: "settings.dream_weight.caption",
                            defaultValue: "Haptic ticks · confirm to save"
                        ),
                        onCommit: { kg in
                            pendingIdealKg = kg
                            if abs(kg - session.profile.idealWeightKg) > 0.05 {
                                confirmDreamWeightChange = true
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("settings.targetWeight")

                    Text(
                        String(
                            format: "Allowed %.0f-%.0f %@",
                            UnitFormat.mass(fromKg: dreamBoundsKg.lowerBound, system: session.preferredUnits),
                            UnitFormat.mass(fromKg: dreamBoundsKg.upperBound, system: session.preferredUnits),
                            session.preferredUnits.massLabel
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(steel)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("settings.targetWeight.bounds")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let weightValidationNote {
                    validationLine(weightValidationNote)
                }

                labeledField(
                    title: "Dream body fat % (optional)",
                    help: "Most people leave this blank. FATNAG suggests a target from sex and age. Override only within physics limits (about 3-60%)."
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            String(
                                format: "Suggested %.0f%% for %@, age %.0f",
                                BodyFatTargetEngine.suggestedIdealPercent(
                                    sex: session.profile.sex,
                                    ageYears: session.profile.ageYears
                                ),
                                session.profile.sex.title.lowercased(),
                                session.profile.ageYears
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(steel)
                        HStack(spacing: 6) {
                            TextField("Blank = suggested", text: $bodyFatText)
                                .focused($focusedField, equals: .bodyFat)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 72)
                                .onChange(of: bodyFatText) { _, newValue in
                                    applyBodyFatText(newValue)
                                }
                                .onChange(of: focusedField) { _, field in
                                    if field != .bodyFat {
                                        syncBodyFatTextFromProfile()
                                    }
                                }
                            Text("%").foregroundStyle(steel)
                            if session.profile.idealBodyFatPercent != nil {
                                Button("Clear") {
                                    session.profile.idealBodyFatPercent = nil
                                    bodyFatText = ""
                                    bodyFatValidationNote = "Using suggested dream body fat again."
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                if let bodyFatValidationNote {
                    validationLine(bodyFatValidationNote)
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

                Text(String(localized: "settings.gender", defaultValue: "Gender"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Picker(
                    "Gender",
                    selection: Binding(
                        get: { pendingSex ?? session.profile.sex },
                        set: { next in
                            guard next != session.profile.sex else { return }
                            pendingSex = next
                            confirmSexChange = true
                        }
                    )
                ) {
                    ForEach(UserBodyProfile.Sex.allCases) { sex in
                        Text(sex.title).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.gender")

                Text(String(localized: "settings.diet", defaultValue: "Diet"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.diet.help",
                    defaultValue: "How you eat most days. Drives meal-plan tone."
                ))
                    .font(.caption2)
                    .foregroundStyle(steel)
                Picker(String(localized: "settings.diet", defaultValue: "Diet"), selection: Binding(
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
        .onAppear {
            draftAgeYears = Int(session.profile.ageYears.rounded())
            syncDraftHeightFromProfile()
            clampIdealWeightFromProfile(announce: false)
        }
        .onChange(of: session.preferredUnits) { _, _ in
            syncDraftHeightFromProfile()
        }
    }

    private func syncDraftHeightFromProfile() {
        draftHeightDisplay = UnitFormat.height(
            fromCm: session.profile.heightCm,
            system: session.preferredUnits
        )
    }

    private func proposeHeightFromDraft() {
        let cm = UnitFormat.cm(fromHeight: draftHeightDisplay, system: session.preferredUnits)
        let result = ProfileNumericBounds.clampHeightCm(cm)
        heightValidationNote = result.message
        draftHeightDisplay = UnitFormat.height(fromCm: result.value, system: session.preferredUnits)
        guard abs(result.value - session.profile.heightCm) > 0.05 else { return }
        pendingHeightCm = result.value
        confirmHeightChange = true
    }

    private func applyPendingHeight() {
        guard let cm = pendingHeightCm else { return }
        session.profile.heightCm = cm
        pendingHeightCm = nil
        clampIdealWeightFromProfile(announce: true)
        syncDraftHeightFromProfile()
    }

    private func proposeAgeFromDraft() {
        let result = ProfileNumericBounds.clampAgeYears(Double(draftAgeYears))
        ageValidationNote = result.message
        draftAgeYears = Int(result.value.rounded())
        guard abs(result.value - session.profile.ageYears) > 0.05 else { return }
        pendingAgeYears = result.value
        confirmAgeChange = true
    }

    private func applyPendingAge() {
        guard let age = pendingAgeYears else { return }
        session.profile.ageYears = age
        pendingAgeYears = nil
        clampIdealWeightFromProfile(announce: true)
    }

    private func applyPendingDreamWeight() {
        guard let kg = pendingIdealKg else { return }
        commitIdealWeightKg(kg)
        pendingIdealKg = nil
    }

    private func applyPendingSex() {
        guard let sex = pendingSex else { return }
        session.profile.sex = sex
        pendingSex = nil
        let result = ProfileRecalibrator.recalibrate(
            profile: session.profile,
            currentKg: session.healthBaselineKg ?? session.profile.startingWeightKg,
            keepBodyFatOverride: session.profile.idealBodyFatPercent != nil
        )
        session.profile.idealWeightKg = result.idealWeightKg
        session.profile.idealBodyFatPercent = result.idealBodyFatPercent
        session.profile.goalDifficultyTitle = result.goalDifficultyTitle
        weightValidationNote = result.note
        session.clearMealPlanCache()
        syncBodyFatTextFromProfile()
    }

    private func commitIdealWeightKg(_ raw: Double) {
        let result = ProfileNumericBounds.clampIdealWeightKg(
            raw,
            heightCm: session.profile.heightCm,
            currentKg: session.healthBaselineKg ?? session.profile.startingWeightKg,
            sex: session.profile.sex,
            ageYears: session.profile.ageYears
        )
        session.profile.idealWeightKg = result.value
        weightValidationNote = result.message
    }

    /// When height / sex / age change, snap stored target into the new BMI-safe band.
    private func clampIdealWeightFromProfile(announce: Bool) {
        let before = session.profile.idealWeightKg
        let result = ProfileNumericBounds.clampIdealWeightKg(
            before,
            heightCm: session.profile.heightCm,
            currentKg: session.healthBaselineKg ?? session.profile.startingWeightKg,
            sex: session.profile.sex,
            ageYears: session.profile.ageYears
        )
        session.profile.idealWeightKg = result.value
        guard announce else {
            if !result.didClamp { weightValidationNote = nil }
            return
        }
        if result.didClamp {
            weightValidationNote = result.message
                ?? "Target adjusted to \(UnitFormat.massString(result.value, system: session.preferredUnits, fractionDigits: 1)) so it stays realistic for your updated profile."
        } else {
            weightValidationNote = nil
        }
    }

    private func labeledField<Content: View>(
        title: String,
        help: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            Text(help)
                .font(.caption2)
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(softPanelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func validationLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.validation")
    }

    private func syncBodyFatTextFromProfile() {
        if let pct = session.profile.idealBodyFatPercent {
            bodyFatText = String(format: "%.1f", pct)
        } else {
            bodyFatText = ""
        }
        bodyFatValidationNote = nil
    }

    private func applyBodyFatText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.profile.idealBodyFatPercent = nil
            bodyFatValidationNote = nil
            return
        }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            bodyFatValidationNote = "Body fat % must be a number, or leave blank if unknown."
            return
        }
        let result = ProfileNumericBounds.clampOptionalBodyFatPercent(value)
        session.profile.idealBodyFatPercent = result.value
        bodyFatValidationNote = result.message
        if let clamped = result.value, result.message != nil {
            bodyFatText = String(format: "%.1f", clamped)
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
                Text(String(localized: "settings.persona", defaultValue: "Persona & AI"))
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.persona.help",
                    defaultValue: "Tone stays on-device until you consent to a live Keel ask."
                ))
                    .font(.footnote)
                    .foregroundStyle(steel)

                labeledField(
                    title: "Location",
                    help: "City or region (e.g. Hong Kong, Manila). Helps meal staples and nearby fitness when the toggle below is on."
                ) {
                    TextField("City or region", text: $session.profile.location)
                        .focused($focusedField, equals: .location)
                        .textContentType(.addressCity)
                }
                Toggle(isOn: $session.profile.useLocalContext) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use location for local food and fitness")
                            .font(.footnote.weight(.semibold))
                        Text("Markets, meal staples, and nearby options when on.")
                            .font(.caption2)
                            .foregroundStyle(steel)
                    }
                }
                .accessibilityIdentifier("settings.useLocalContext")

                labeledField(
                    title: "Food avoidances / allergies",
                    help: "Hard nos for meal plans (peanuts, shellfish, no dairy). Leave blank if none."
                ) {
                    TextField(
                        "e.g. peanuts, shellfish",
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
                }

                labeledField(
                    title: "Medical / habits (optional)",
                    help: "Injuries, meds, alcohol, sleep quirks. On-device Coach context only; not a diagnosis."
                ) {
                    TextField(
                        "e.g. knee tweak, weekend wine",
                        text: $session.profile.healthContextNotes,
                        axis: .vertical
                    )
                    .focused($focusedField, equals: .healthContext)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("settings.healthContext")
                }

                labeledField(
                    title: "Ethnicity / culture (optional)",
                    help: "Only what you want Keel to respect in tone and food examples."
                ) {
                    TextField("Optional", text: $session.profile.ethnicity)
                        .focused($focusedField, equals: .ethnicity)
                }

                labeledField(
                    title: "Vibe / cultural style (optional)",
                    help: "Short coach-facing note (e.g. direct, soft, Filipina in HK)."
                ) {
                    TextField(
                        "Short note for Keel",
                        text: $session.profile.culturalVibe,
                        axis: .vertical
                    )
                    .focused($focusedField, equals: .vibe)
                    .lineLimit(2...4)
                }

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

                Text(OnDevicePolishBootstrap.combinedStatusSummary)
                    .font(.caption)
                    .foregroundStyle(steel)
                Text("Apple Intelligence phones use the system model. Other compatible iPhones auto-install a private 0.5B Metal polish pack (~470 MB, Wi-Fi). Keel handles live Coach when consented.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                if case .ready = onDevicePolish.snapshot.phase {
                    Text("Installed: \(OnDevicePolishCatalog.displayName)")
                        .font(.caption2)
                        .foregroundStyle(steel)
                } else if case .failed = onDevicePolish.snapshot.phase {
                    Button("Retry on-device polish download") {
                        Task { await OnDevicePolishInstaller.shared.startDownload() }
                    }
                    .font(.caption)
                } else if case .needsInstall = onDevicePolish.snapshot.phase {
                    Button("Download on-device polish") {
                        Task { await OnDevicePolishInstaller.shared.startDownload() }
                    }
                    .font(.caption)
                } else if case .downloading(let progress) = onDevicePolish.snapshot.phase {
                    ProgressView(value: progress)
                    Text("Downloading on-device polish…")
                        .font(.caption2)
                        .foregroundStyle(steel)
                }
            }
        }
    }

    // MARK: - Alerts

    private var notificationsCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 0) {
                Label {
                    Text(String(localized: "settings.notifications", defaultValue: "Notifications"))
                } icon: {
                    Image(systemName: "bell.badge")
                }
                    .font(.headline)
                    .foregroundStyle(ink)

                Text(String(
                    localized: "settings.alerts.help",
                    defaultValue: "Local banners with actions. Focus and Do Not Disturb can still silence them."
                ))
                    .font(.footnote)
                    .foregroundStyle(steel)
                    .padding(.top, 6)

                notificationsSubsectionDivider(title: String(localized: "notif.permission", defaultValue: "Permission"))

                Text(notificationAuthLine)
                    .font(.caption)
                    .foregroundStyle(notificationAuthDenied ? Color.orange : steel)
                    .fixedSize(horizontal: false, vertical: true)

                if notificationAuthDenied {
                    Text("Coach cannot fire drills while denied. Tap System, then allow alerts for FATNAG.")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
                            await session.refreshTrendNotifications()
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
                .padding(.top, 10)

                notificationsSubsectionDivider(title: "What you get")

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

                notificationsSubsectionDivider(title: "Morning weigh")

                Toggle(
                    "Morning weigh drill",
                    isOn: Binding(
                        get: { session.notificationPreferences.morningWeighDrill },
                        set: {
                            var next = session.notificationPreferences
                            next.morningWeighDrill = $0
                            session.notificationPreferences = next
                            Task {
                                await session.considerMorningWeighDrill()
                                await refreshNotificationStatus()
                            }
                        }
                    )
                )
                Text("About 06:30 local, or soon after Health wake. Window closes at 08:00. Skips the day if you already weighed.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .padding(.top, 2)

                if session.notificationPreferences.morningWeighDrill {
                    HStack {
                        Text("Fallback clock (before 8:00)")
                            .font(.caption)
                            .foregroundStyle(steel)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: {
                                    var comps = Calendar.current.dateComponents(
                                        [.year, .month, .day],
                                        from: Date()
                                    )
                                    comps.hour = session.notificationPreferences.morningWeighFallbackHour
                                    comps.minute = session.notificationPreferences.morningWeighFallbackMinute
                                    return Calendar.current.date(from: comps) ?? Date()
                                },
                                set: {
                                    let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                    let clamped = ProfileNumericBounds.clampMorningFallback(
                                        hour: comps.hour ?? NotificationPreferences.defaultMorningFallbackHour,
                                        minute: comps.minute ?? NotificationPreferences.defaultMorningFallbackMinute
                                    )
                                    var next = session.notificationPreferences
                                    next.morningWeighFallbackHour = clamped.hour
                                    next.morningWeighFallbackMinute = clamped.minute
                                    session.notificationPreferences = next
                                    Task {
                                        await session.considerMorningWeighDrill()
                                        await refreshNotificationStatus()
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.top, 8)
                }

                if !pendingCoachReminders.isEmpty {
                    notificationsSubsectionDivider(title: "Coach reminders")

                    ForEach(pendingCoachReminders) { item in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ink)
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
                        .padding(.vertical, 2)
                    }
                    Button("Cancel all Coach reminders") {
                        Task {
                            await CoachReminderScheduler.cancelAllCoachReminders()
                            await refreshNotificationStatus()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func notificationsSubsectionDivider(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 12)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(steel.opacity(0.95))
        }
    }

    private func refreshNotificationStatus() async {
        let detail = await TrendNotificationScheduler.authorizationStatusDetail()
        notificationAuthLine = await CoachReminderScheduler.authorizationStatusLine()
        if detail.isDenied {
            notificationAuthLine = detail.line
        }
        notificationAuthDenied = detail.isDenied
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
                        Label {
                            Text(String(localized: "settings.allow_health", defaultValue: "Allow Health"))
                        } icon: {
                            Image(systemName: "heart.text.square.fill")
                        }
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
                Text("Every 10 minutes the phone reads steps, workouts, and sleep. A new beat arrives as Nag: a greeting, a joke, a reward, or a hard nudge. Empty check-ins are not sent. iOS may delay background wakes.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)

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
                Label(String(localized: "settings.calibration", defaultValue: "Weight calibration"), systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(String(
                    localized: "settings.calibration.help",
                    defaultValue: "Enter true mass, open the live sheet, weigh, then store."
                ))
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
                    session.dismissSettings()
                } label: {
                    Label("Weigh reference on live sheet", systemImage: "scalemass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

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

    private var feedbackCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Feedback", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("Bug, idea, or praise — one short note. Optional email if you want a reply.")
                    .font(.footnote)
                    .foregroundStyle(steel)
                Button {
                    showFeedback = true
                } label: {
                    Label {
                        Text(String(localized: "settings.send_feedback", defaultValue: "Send feedback"))
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("settings.sendFeedback")
            }
        }
    }

    private var privacyCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Privacy", systemImage: "lock.shield")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text("On-device first. Keel Coach is opt-in. No ads. No sale of personal data. GDPR and US state rights supported.")
                    .font(.footnote)
                    .foregroundStyle(steel)

                Text(ScaleLegal.privacyPolicyShortSummary)
                    .font(.caption2)
                    .foregroundStyle(steel)

                NavigationLink {
                    LegalDocumentView(document: .privacyPolicy)
                } label: {
                    Label("Privacy Policy (EU GDPR)", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.privacyPolicy")

                NavigationLink {
                    LegalDocumentView(document: .usStatePrivacy)
                } label: {
                    Label("US State Privacy Notice", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.usPrivacy")

                Link(destination: ScaleLegal.privacyPolicyURL) {
                    Label("Privacy Policy (web)", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.privacyPolicyWeb")

                Link(destination: ScaleLegal.termsOfUseURL) {
                    Label("Terms of Use (web)", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.termsWeb")

                Text("Web links open our public Privacy Policy and Terms. Full copies also live in Settings above.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                Link(destination: ScaleLegal.privacyMailtoURL) {
                    Label("Email \(ScaleLegal.privacyEmail)", systemImage: "envelope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.privacyEmail")

                Divider().padding(.vertical, 2)

                Text("Your data rights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)

                Button {
                    exportLocalData()
                } label: {
                    Label {
                        Text(String(localized: "settings.export_data", defaultValue: "Export my data"))
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.exportData")

                Button(role: .destructive) {
                    showEraseConfirm = true
                } label: {
                    Label {
                        Text(String(localized: "settings.erase_data", defaultValue: "Erase my data"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.eraseData")

                Text("Erase clears FATNAG’s on-device profile, Coach history, and preferences, then returns you to onboarding. Apple Health samples are not deleted; manage those in the Health app.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                #if DEBUG
                Divider().padding(.vertical, 2)

                Text("Debug · Promo demos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)

                Text("Loads a full camera-ready persona (profile, 4 weeks of weighs, gauges, meals, Keel chat) and writes Steps / Energy / Diet / Sleep / Workouts into HealthKit. Tap Turn On All on the Health share sheet once.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                Button {
                    session.applyDemoPersona(.male)
                    dataRightsNote = "Demo male (Bob) loaded. Allow Health write to inject Steps + activity into the Simulator Health app."
                    session.dismissSettings()
                } label: {
                    Label("Load demo · Male (Bob) + HealthKit", systemImage: "person.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.demoMale")

                Button {
                    session.applyDemoPersona(.female)
                    dataRightsNote = "Demo female (Alice) loaded. Allow Health write to inject Steps + activity into the Simulator Health app."
                    session.dismissSettings()
                } label: {
                    Label("Load demo · Female (Alice) + HealthKit", systemImage: "person.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.demoFemale")
                #endif

                if let dataRightsNote {
                    Text(dataRightsNote)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .confirmationDialog(
            "Erase all FATNAG data on this iPhone?",
            isPresented: $showEraseConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                ScaleDataRights.eraseAllLocalData(session: session)
                dataRightsNote = "Local data erased. Complete onboarding again when ready."
                session.dismissSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Health app data stays unless you delete it there.")
        }
        .sheet(item: Binding(
            get: { exportShareURL.map { ExportShareItem(url: $0) } },
            set: { exportShareURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
    }

    private var legalCard: some View {
        settingsPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Legal", systemImage: "doc.text")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(CoachCopySanitize.medicalDisclaimer)
                    .font(.caption)
                    .foregroundStyle(steel)
                Text("Shown at onboarding. Coach chat and notifications do not repeat this.")
                    .font(.caption2)
                    .foregroundStyle(steel)

                ForEach(ScaleLegal.Document.allCases.filter { $0 != .privacyPolicy && $0 != .usStatePrivacy }) { doc in
                    NavigationLink {
                        LegalDocumentView(document: doc)
                    } label: {
                        Label(doc.title, systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.legal.\(doc.rawValue)")
                }

                Text("Age gate: \(ScaleLegal.minimumAgeYears)+. Controller: \(ScaleLegal.controllerName).")
                    .font(.caption2)
                    .foregroundStyle(steel)

                if let accepted = LegalAcceptanceStore.acceptedAt {
                    Text("Terms accepted: \(accepted.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(steel)
                        .accessibilityIdentifier("settings.legalAcceptedAt")
                }
            }
        }
    }

    private func exportLocalData() {
        do {
            let data = try ScaleDataRights.exportLocalDataJSON(profile: session.profile)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("fatnag-data-export.json")
            try data.write(to: url, options: .atomic)
            exportShareURL = url
            dataRightsNote = "Export ready to share or save."
        } catch {
            dataRightsNote = "Export failed: \(error.localizedDescription)"
        }
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

private struct ExportShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Minimal UIKit share sheet wrapper for JSON export.
private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ScaleSessionViewModel())
    }
}
