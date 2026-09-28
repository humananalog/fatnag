import SwiftUI

/// Card carousel for next-24h meals (interaction surface; OK to use cards here).
struct MealPlanCarouselView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0

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

    private let peek: CGFloat = 28
    private let cardGap: CGFloat = 12

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

                VStack(alignment: .leading, spacing: 16) {
                    headerCopy

                    if let plan = session.mealPlan, !plan.meals.isEmpty {
                        GeometryReader { geo in
                            // GeometryReader can report 0 during the first layout pass; never
                            // feed negative / non-finite sizes into `.frame`.
                            let safeWidth = geo.size.width.isFinite ? max(0, geo.size.width) : 0
                            let safeHeight = geo.size.height.isFinite ? max(0, geo.size.height) : 0
                            let cardWidth = max(240, safeWidth - peek * 2)
                            let cardHeight = max(1, safeHeight - 8)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: cardGap) {
                                    ForEach(Array(plan.meals.enumerated()), id: \.element.id) { index, meal in
                                        mealCard(meal, accent: accents[index % accents.count])
                                            .frame(width: cardWidth, height: cardHeight)
                                            .id(index)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .contentMargins(.horizontal, peek, for: .scrollContent)
                            .scrollTargetBehavior(.viewAligned)
                            .scrollPosition(id: Binding<Int?>(
                                get: { pageIndex },
                                set: { pageIndex = $0 ?? 0 }
                            ))
                        }
                        .frame(maxHeight: .infinity)

                        pageDots(count: plan.meals.count)

                        Text(plan.sourceNote)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(steel)
                            .padding(.horizontal, 4)
                    } else {
                        Spacer(minLength: 12)
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(ink.opacity(0.2), lineWidth: 1.5)
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                            Text(session.isMealPlanLoading
                                 ? String(localized: "meal.writing", defaultValue: "Keel is writing meals. You can keep moving.")
                                 : String(localized: "meal.empty", defaultValue: "No meal plan yet."))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 8)
                        Spacer(minLength: 12)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
            }
            .navigationTitle(String(localized: "meal.title", defaultValue: "Meal plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.refresh", defaultValue: "Refresh")) {
                        Task { await session.refreshMealPlan(force: true) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.alreadyWeighedToday {
                        Button(String(localized: "common.manual", defaultValue: "Manual")) { session.presentManualEntry() }
                    } else if session.weighNowGateResolved {
                        Button(String(localized: "common.weigh", defaultValue: "Weigh")) { session.selectHomeTab(.weigh) }
                    }
                }
            }
            .task {
                session.refreshAlreadyWeighedToday()
                await session.ensureMealPlan()
            }
            .onChange(of: session.mealPlan?.meals.count ?? 0) { _, _ in
                pageIndex = 0
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "meal.whats_ahead", defaultValue: "What's ahead"))
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            if let plan = session.mealPlan {
                Text(String(
                    format: String(localized: "meal.cap_line", defaultValue: "Cap %d kcal · protein %d g · %@"),
                    plan.maxKcal,
                    plan.proteinGrams,
                    plan.dietRaw
                ))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            } else {
                Text(String(localized: "meal.grounded", defaultValue: "Grounded in your deficit, diet prefs, and fasting window."))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            }
        }
        .padding(.horizontal, 8)
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? ink : ink.opacity(0.22))
                    .frame(width: index == pageIndex ? 18 : 8, height: 8)
                    .accessibilityLabel("Page \(index + 1) of \(count)")
                    .accessibilityAddTraits(index == pageIndex ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal pages")
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
                labeled(String(localized: "meal.macro", defaultValue: "Macro"), meal.keyMacro, accent: accent)
                labeled(String(localized: "meal.micro", defaultValue: "Micro"), meal.keyMicro, accent: accent)
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

#Preview {
    MealPlanCarouselView()
        .environmentObject(ScaleSessionViewModel())
}
