import SwiftUI

/// Slow-motion diffused haze behind the weekly-goal hero. Subtle, not noisy.
struct WeeklyGoalHazeBackground: View {
    let atmosphere: WeeklyGoalAtmosphere

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slow = t / 18.0
            let x1 = CGFloat(sin(slow) * 0.12)
            let y1 = CGFloat(cos(slow * 0.7) * 0.10)
            let x2 = CGFloat(cos(slow * 0.55) * 0.14)
            let y2 = CGFloat(sin(slow * 0.9) * 0.11)
            let x3 = CGFloat(sin(slow * 0.4 + 1.2) * 0.10)
            let y3 = CGFloat(cos(slow * 0.65 + 0.8) * 0.13)

            ZStack {
                LinearGradient(
                    colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Ellipse()
                    .fill(atmosphere.hazeA)
                    .frame(width: 340, height: 280)
                    .blur(radius: 52)
                    .offset(x: -80 + x1 * 160, y: -120 + y1 * 140)

                Ellipse()
                    .fill(atmosphere.hazeB)
                    .frame(width: 380, height: 300)
                    .blur(radius: 60)
                    .offset(x: 90 + x2 * 150, y: 40 + y2 * 160)

                Ellipse()
                    .fill(atmosphere.hazeA.opacity(0.65))
                    .frame(width: 260, height: 220)
                    .blur(radius: 44)
                    .offset(x: 20 + x3 * 120, y: 180 + y3 * 100)
            }
            .ignoresSafeArea()
        }
    }
}

/// Home: one weekly-goal composition. No card chrome. Haze atmosphere only.
struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    #if DEBUG
    @State private var showDebugTools = false
    #endif

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(surface.band)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WeeklyGoalHazeBackground(atmosphere: atmosphere)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        brandRow
                            .padding(.top, 4)

                        weeklyHero
                            .padding(.top, 20)

                        tomorrowBlock
                            .padding(.top, 26)

                        targetsRow
                            .padding(.top, 28)

                        Text(surface.targets.honestyLine)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.ink.opacity(0.72))
                            .padding(.top, 10)

                        primaryActions
                            .padding(.top, 30)

                        discoveryBlock
                            .padding(.top, 12)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDebugTools = true
                    } label: {
                        Text("DEBUG")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.92), in: Capsule())
                    }
                    .accessibilityIdentifier("home.debug")
                    .accessibilityLabel("Debug tools")
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(atmosphere.ink)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            #if DEBUG
            .sheet(isPresented: $showDebugTools) {
                DebugToolsView()
                    .environmentObject(session)
            }
            #endif
            .sheet(isPresented: Binding(
                get: { session.isSettingsPresented },
                set: { if !$0 { session.dismissSettings() } }
            )) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(session)
                }
            }
            .sheet(isPresented: Binding(
                get: { session.isMealPlanPresented },
                set: { if !$0 { session.dismissMealPlan() } }
            )) {
                MealPlanCarouselView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isWeighInPresented },
                set: { if !$0 { session.dismissWeighIn() } }
            )) {
                LiveWeighInSheet()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isResultsPresented },
                set: { if !$0 { session.dismissResults() } }
            )) {
                WeighInResultsView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isManualEntryPresented && !session.isResultsPresented },
                set: { if !$0 { session.dismissManualEntry() } }
            )) {
                ManualWeighInView()
                    .environmentObject(session)
            }
            .sheet(isPresented: Binding(
                get: { session.isProgressPresented },
                set: { if !$0 { session.dismissProgress() } }
            )) {
                ProgressSheet()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isCoachPresented },
                set: { if !$0 { session.dismissCoach() } }
            )) {
                CoachChatView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isMondayCardPresented },
                set: { if !$0 { session.dismissMondayCard() } }
            )) {
                MondayWeeklyCardView()
                    .environmentObject(session)
            }
            .sheet(isPresented: Binding(
                get: { session.isAppReviewPromptPresented },
                set: { if !$0 { session.dismissAppReviewPrompt() } }
            )) {
                AppReviewPromptView {
                    session.dismissAppReviewPrompt()
                }
            }
            .task {
                session.ensureWeeklyGoalBaseline()
                session.rebuildWeeklyGoalSurface()
                await session.refreshHealthBaseline()
                session.ensureWeeklyGoalBaseline()
                await session.refreshWeeklyGoalSurface()
                await session.refreshTrendNotifications()
                ScaleNotificationRouter.openDestination = { destination in
                    session.handleNotificationDestination(destination)
                }
                ScaleNotificationRouter.openAppNotificationSettings = {
                    session.presentSettings()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var brandRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("The Scale")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(atmosphere.ink)
                    .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                Text(greetingLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.ink.opacity(0.78))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(brandAccessibilityLabel)
    }

    private var greetingLine: String {
        let name = session.profile.greetingName
        if let kg = session.healthBaselineKg {
            if name.isEmpty {
                return String(format: "%.1f kg · this week", kg)
            }
            return String(format: "%@ · %.1f kg", name, kg)
        }
        if name.isEmpty { return "Weekly goal" }
        return "\(name) · weekly goal"
    }

    private var brandAccessibilityLabel: String {
        let name = session.profile.greetingName
        if let baseline = session.healthBaselineKg {
            if name.isEmpty {
                return String(format: "The Scale. Last Health weight %.1f kilograms.", baseline)
            }
            return String(format: "The Scale. Hello %@. Last Health weight %.1f kilograms.", name, baseline)
        }
        if name.isEmpty { return "The Scale" }
        return "The Scale. Hello \(name)."
    }

    private var weeklyHero: some View {
        Button {
            session.presentProgress()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(surface.completionPercent)%")
                        .font(.system(size: 78, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(atmosphere.ink)
                        .shadow(color: .white.opacity(0.65), radius: 0, y: 1)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(surface.band.statusLabel.uppercased())
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(atmosphere.ink)
                        Text("of week goal")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.ink.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }

                Text(surface.weekTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(atmosphere.ink)

                Text(surface.detailLine)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Progress")
    }

    private var tomorrowBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tomorrow")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1.0)

            Text(surface.tomorrowAdvice)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(atmosphere.ink)
                .shadow(color: .white.opacity(0.45), radius: 0, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var targetsRow: some View {
        let t = surface.targets
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                targetCell(value: "\(t.steps)", unit: "steps", caption: "Target")
                targetCell(value: "\(t.maxCalories)", unit: "kcal max", caption: "Energy")
            }
            HStack(alignment: .top, spacing: 20) {
                targetCell(value: "\(t.proteinGrams) g", unit: t.proteinLabel, caption: "Hit")
                targetCell(value: t.microName, unit: t.microTargetLine, caption: "Micro")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Targets. \(t.steps) steps. Max \(t.maxCalories) calories. Protein \(t.proteinGrams) grams. \(t.microName) \(t.microTargetLine). \(t.honestyLine)."
        )
    }

    private func targetCell(value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.65))
                .tracking(0.7)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.ink)
                .shadow(color: .white.opacity(0.4), radius: 0, y: 1)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(unit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            Button {
                session.startScanning()
            } label: {
                Text(session.phase == .scanning ? "Scanning…" : "Find Scale")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(atmosphere.ink)
            .disabled(session.phase == .scanning || session.phase == .healthKitWriting)

            HStack(spacing: 8) {
                homeSecondaryButton(title: "Coach", systemImage: "sparkles") {
                    session.presentCoach()
                }
                homeSecondaryButton(title: "Meals", systemImage: "fork.knife") {
                    session.presentMealPlan()
                }
                homeSecondaryButton(title: "History", systemImage: "chart.xyaxis.line") {
                    session.reopenResults()
                }
            }

            Button {
                session.presentManualEntry()
            } label: {
                Label("Manual weigh-in", systemImage: "pencil.line")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(atmosphere.ink.opacity(0.8))

            if session.selectedScaleID != nil {
                Button {
                    session.reopenWeighIn()
                } label: {
                    Text("Weigh in")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(atmosphere.ink.opacity(0.72))
            }

            if case .healthKitSuccess = session.phase, !session.isWeighInPresented {
                Text("Saved to Health")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.06, green: 0.32, blue: 0.20))
            }

            if !session.healthKitAvailable {
                Text("Health unavailable on this device.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(atmosphere.ink.opacity(0.7))
            }
        }
    }

    private func homeSecondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(atmosphere.ink)
    }

    @ViewBuilder
    private var discoveryBlock: some View {
        switch session.phase {
        case .scanning where session.discoveredScales.isEmpty:
            ProgressView()
                .padding(.top, 16)
                .tint(atmosphere.ink)
        case .bluetoothUnavailable(let message):
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.06, blue: 0.06))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        default:
            if session.discoveredScales.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.discoveredScales) { scale in
                        Button {
                            session.selectScale(scale)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scale.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(atmosphere.ink)
                                    Text("RSSI \(scale.rssi) dBm")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(atmosphere.ink.opacity(0.7))
                                }
                                Spacer()
                                if session.selectedScaleID == scale.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(atmosphere.ink)
                                }
                            }
                            .padding(.vertical, 14)
                        }
                        if scale.id != session.discoveredScales.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
