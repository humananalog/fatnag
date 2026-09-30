import SwiftUI

/// Card carousel for next-24h meals (interaction surface; OK to use cards here).
struct MealPlanCarouselView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.95, blue: 0.92)
            : Color(red: 0.06, green: 0.07, blue: 0.09)
    }

    private var steel: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.72, blue: 0.76)
            : Color(red: 0.28, green: 0.30, blue: 0.34)
    }

    private var sheetTop: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.08, blue: 0.10)
            : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    private var sheetBottom: Color {
        colorScheme == .dark
            ? Color(red: 0.04, green: 0.05, blue: 0.07)
            : Color(red: 0.90, green: 0.93, blue: 0.96)
    }

    private let accents: [Color] = [
        Color(red: 0.18, green: 0.52, blue: 0.62),
        Color(red: 0.78, green: 0.42, blue: 0.22),
        Color(red: 0.32, green: 0.55, blue: 0.38),
        Color(red: 0.48, green: 0.36, blue: 0.68)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [sheetTop, sheetBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let focus = session.mealPlan.map {
                        MealPlanEngine.focus(
                            meals: $0.meals,
                            now: context.date,
                            fasting: fastingWindow
                        )
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        headerCopy(focus: focus)

                        if let plan = session.mealPlan, !plan.meals.isEmpty, let focus {
                            switch focus {
                            case .kitchenClosed:
                                KitchenClosedHero(ink: ink, steel: steel)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            case .next(let meal):
                                mealCard(meal, accent: accents[0])
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(plan.sourceNote)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(steel)
                                    .padding(.horizontal, 4)
                            }
                        } else {
                            emptyPlan
                        }
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, ScaleLayout.pageInset)
                .padding(.bottom, ScaleLayout.tabBarClearance)
            }
            .navigationTitle(AppLanguageStore.text("meal.title", default: "Meal plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageStore.text("common.refresh", default: "Refresh")) {
                        Task { await session.refreshMealPlan(force: true) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.alreadyWeighedToday {
                        Button(AppLanguageStore.text("common.manual", default: "Manual")) { session.presentManualEntry() }
                    } else if session.weighNowGateResolved {
                        Button(AppLanguageStore.text("common.weigh", default: "Weigh")) { session.selectHomeTab(.weigh) }
                    }
                }
            }
            .task {
                session.refreshAlreadyWeighedToday()
                await session.ensureMealPlan()
            }
        }
    }

    private var fastingWindow: FastingWindow {
        FastingWindowResolver.current(profile: session.profile)
    }

    private func headerCopy(focus: MealPlanFocus?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if focus == .kitchenClosed {
                Text(AppLanguageStore.text("meal.kitchen_closed", default: "Kitchen's closed"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            } else {
                Text(AppLanguageStore.text("meal.next_plate", default: "Next plate"))
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                if let plan = session.mealPlan {
                    Text(String(
                        format: AppLanguageStore.text("meal.cap_line", default: "Cap %d kcal · protein %d g · %@"),
                        plan.maxKcal,
                        plan.proteinGrams,
                        plan.dietRaw
                    ))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(steel)
                } else {
                    Text(AppLanguageStore.text("meal.grounded", default: "Grounded in your deficit, diet prefs, and fasting window."))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(steel)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var emptyPlan: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 20)
            Image(systemName: "fork.knife")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accents.first ?? ink)
                .frame(width: 56, height: 56)
                .background((accents.first ?? ink).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(session.isMealPlanLoading
                 ? AppLanguageStore.text("meal.writing", default: "Keel is writing meals. You can keep moving.")
                 : AppLanguageStore.text("meal.empty", default: "No meal plan yet."))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            if !session.isMealPlanLoading {
                Text(AppLanguageStore.text("meal.empty.hint", default: "Pull refresh, or weigh in — Keel fills the plate from your deficit."))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func mealCard(_ meal: MealPlanMeal, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 6)

            HStack(alignment: .firstTextBaseline) {
                Text(meal.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Text(meal.timeLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.14), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(meal.ingredients, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(accent.opacity(0.85))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(line)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 16) {
                labeled(AppLanguageStore.text("meal.macro", default: "Macro"), meal.keyMacro, accent: accent)
                labeled(AppLanguageStore.text("meal.micro", default: "Micro"), meal.keyMicro, accent: accent)
            }

            Text("~\(meal.approxKcal) kcal")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [sheetTop, sheetBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: ink.opacity(0.06), radius: 10, y: 4)
    }

    private func labeled(_ caption: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            (AppLanguageStore.text("meal.late.too", default: "Too late"), 72, .bold, .serif, false),
            (AppLanguageStore.text("meal.late.eat", default: "to eat now."), 44, .semibold, .serif, false),
            (AppLanguageStore.text("meal.late.bed", default: "Go to bed."), 60, .bold, .rounded, false),
            (AppLanguageStore.text("meal.late.hungry", default: "You won't be hungry."), 32, .semibold, .rounded, true)
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion)) { context in
            let counts = lineCounts(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(String(line.text.prefix(counts[index])))
                        .font(.system(size: line.size, weight: line.weight, design: line.design))
                        .foregroundStyle(line.muted ? steel : ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: line.size * 1.05, alignment: .leading)
                        .opacity(counts[index] == 0 ? 0 : 1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLanguageStore.text("meal.late.a11y", default: "Too late to eat now. Go to bed. You won't be hungry."))
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
