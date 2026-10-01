import SwiftUI

/// Meals tab: kitchen plate board — next meal as the one composition, not a SaaS card stack.
struct MealPlanCarouselView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plateIn = false

    private var universe: ScalePaletteUniverse {
        .resolve(sex: session.profile.sex)
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(
            session.weeklyGoalSurface.band,
            colorScheme: colorScheme,
            universe: universe
        )
    }

    private var ink: Color { atmosphere.ink }
    private var steel: Color { atmosphere.muted }
    private var accent: Color {
        colorScheme == .dark
            ? ScaleChrome.signal(for: universe)
            : ScaleChrome.ember(for: universe)
    }

    private var baseFill: Color {
        colorScheme == .dark ? atmosphere.mid : atmosphere.top
    }

    var body: some View {
        NavigationStack {
            ZStack {
                atmosphereField

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let focus = session.mealPlan.map {
                        MealPlanEngine.focus(
                            meals: $0.meals,
                            now: context.date,
                            fasting: fastingWindow
                        )
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            switch focus {
                            case .kitchenClosed:
                                KitchenClosedHero(ink: ink, steel: steel)
                                    .frame(minHeight: 420, alignment: .topLeading)
                            case .next(let meal):
                                nextPlate(meal)
                            case .none:
                                emptyPlan
                            }
                        }
                        .padding(.horizontal, ScaleLayout.pageInset)
                        .padding(.top, 12)
                        .padding(.bottom, ScaleLayout.tabBarClearance + 12)
                        .opacity(plateIn || reduceMotion ? 1 : 0)
                        .offset(y: plateIn || reduceMotion ? 0 : 18)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageStore.text("common.refresh", default: "Refresh")) {
                        Task { await session.refreshMealPlan(force: true) }
                    }
                    .foregroundStyle(ink.opacity(0.85))
                }
                ToolbarItem(placement: .principal) {
                    ScaleEyebrow(
                        title: AppLanguageStore.text("meal.title", default: "Meal plan"),
                        color: steel,
                        loud: false
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.alreadyWeighedToday {
                        Button(AppLanguageStore.text("common.manual", default: "Manual")) {
                            session.presentManualEntry()
                        }
                        .foregroundStyle(ink.opacity(0.85))
                    } else if session.weighNowGateResolved {
                        Button(AppLanguageStore.text("common.weigh", default: "Weigh")) {
                            session.selectHomeTab(.weigh)
                        }
                        .foregroundStyle(accent)
                    }
                }
            }
            .toolbarBackground(baseFill.opacity(0.92), for: .navigationBar)
            .task {
                session.refreshAlreadyWeighedToday()
                await session.ensureMealPlan()
            }
            .onAppear { playEntrance() }
            .onChange(of: session.mealPlan?.cacheKey) { _, _ in
                plateIn = false
                playEntrance()
            }
        }
    }

    private var atmosphereField: some View {
        ZStack {
            LinearGradient(
                colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(atmosphere.hazeA)
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -90, y: -140)
            Circle()
                .fill(atmosphere.hazeB)
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 110, y: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var fastingWindow: FastingWindow {
        FastingWindowResolver.current(profile: session.profile)
    }

    // MARK: - Next plate (one composition)

    @ViewBuilder
    private func nextPlate(_ meal: MealPlanMeal) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ScaleEyebrow(
                title: AppLanguageStore.text("meal.next_plate", default: "Next plate"),
                color: accent,
                loud: true
            )

            Text(meal.title)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.72)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(meal.timeLabel)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                Text("·")
                    .foregroundStyle(steel.opacity(0.5))
                Text("~\(meal.approxKcal) kcal")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(steel)
            }

            if let plan = session.mealPlan {
                Text(
                    String(
                        format: AppLanguageStore.text(
                            "meal.cap_line",
                            default: "Cap %d kcal · protein %d g · %@"
                        ),
                        plan.maxKcal,
                        plan.proteinGrams,
                        plan.dietRaw
                    )
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(ink.opacity(colorScheme == .dark ? 0.22 : 0.12))
                .frame(height: 1)
                .padding(.vertical, 4)

            ingredientBoard(meal.ingredients)

            macroStrip(meal: meal)

            if let plan = session.mealPlan {
                laterPlates(plan: plan, current: meal)
                Text(plan.sourceNote)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(steel.opacity(0.85))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ingredientBoard(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScaleEyebrow(
                title: AppLanguageStore.text("meal.on_the_plate", default: "On the plate"),
                color: steel
            )
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent.opacity(0.85))
                        .frame(width: 28, alignment: .leading)
                    Text(line)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func macroStrip(meal: MealPlanMeal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(ink.opacity(colorScheme == .dark ? 0.22 : 0.12))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageStore.text("meal.macro", default: "Macro").uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(steel)
                    Text(meal.keyMacro)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguageStore.text("meal.micro", default: "Micro").uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(steel)
                    Text(meal.keyMicro)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Quiet later-board — text only, no card stack.
    @ViewBuilder
    private func laterPlates(plan: MealPlanPayload, current: MealPlanMeal) -> some View {
        let rest = plan.meals.filter { $0.id != current.id }
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ScaleEyebrow(
                    title: AppLanguageStore.text("meal.later", default: "Later"),
                    color: steel
                )
                ForEach(rest) { meal in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(meal.timeLabel)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(steel)
                            .frame(width: 64, alignment: .leading)
                        Text(meal.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.88))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text("\(meal.approxKcal)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(steel)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 8)
        }
    }

    private var emptyPlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScaleEyebrow(
                title: AppLanguageStore.text("meal.title", default: "Meal plan"),
                color: accent,
                loud: true
            )
            Text(
                session.isMealPlanLoading
                    ? AppLanguageStore.text("meal.writing", default: "Keel is writing meals. You can keep moving.")
                    : AppLanguageStore.text("meal.empty", default: "No meal plan yet.")
            )
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)

            if !session.isMealPlanLoading {
                Text(
                    AppLanguageStore.text(
                        "meal.empty.hint",
                        default: "Pull refresh, or weigh in — Keel fills the plate from your deficit."
                    )
                )
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
    }

    private func playEntrance() {
        guard !reduceMotion else {
            plateIn = true
            return
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            plateIn = true
        }
    }
}

/// Late-night plate: large type that streams in, one line after another.
private struct KitchenClosedHero: View {
    var ink: Color
    var steel: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = Date()

    private var lines: [(text: String, size: CGFloat, weight: Font.Weight, design: Font.Design, muted: Bool)] {
        [
            (AppLanguageStore.text("meal.late.too", default: "Too late"), 72, .bold, .rounded, false),
            (AppLanguageStore.text("meal.late.eat", default: "to eat now."), 44, .semibold, .rounded, false),
            (AppLanguageStore.text("meal.late.bed", default: "Go to bed."), 60, .bold, .rounded, false),
            (AppLanguageStore.text("meal.late.hungry", default: "You won't be hungry."), 28, .semibold, .rounded, true)
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion)) { context in
            let counts = lineCounts(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                ScaleEyebrow(
                    title: AppLanguageStore.text("meal.kitchen_closed", default: "Kitchen's closed"),
                    color: steel,
                    loud: true
                )
                .padding(.bottom, 8)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(String(line.text.prefix(counts[index])))
                        .font(.system(size: line.size, weight: line.weight, design: line.design))
                        .foregroundStyle(line.muted ? steel : ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: line.size * 1.02, alignment: .leading)
                        .opacity(counts[index] == 0 ? 0 : 1)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLanguageStore.text(
                "meal.late.a11y",
                default: "Too late to eat now. Go to bed. You won't be hungry."
            )
        )
        .onAppear { anchor = Date() }
    }

    private func lineCounts(at date: Date) -> [Int] {
        if reduceMotion { return lines.map { $0.text.count } }
        let rate = 0.048
        let gap = 0.22
        var cursor = 0.0
        let elapsed = date.timeIntervalSince(anchor)
        return lines.map { line in
            let start = cursor
            cursor += Double(line.text.count) * rate + gap
            if elapsed <= start { return 0 }
            return min(line.text.count, Int((elapsed - start) / rate))
        }
    }
}

#Preview {
    MealPlanCarouselView()
        .environmentObject(ScaleSessionViewModel())
}
