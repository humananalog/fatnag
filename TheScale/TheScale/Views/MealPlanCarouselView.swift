import SwiftUI

/// Card carousel for next-24h meals (interaction surface; OK to use cards here).
struct MealPlanCarouselView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.06, green: 0.07, blue: 0.09)
    private let steel = Color(red: 0.28, green: 0.30, blue: 0.34)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.98).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    headerCopy

                    if session.isMealPlanLoading {
                        Spacer()
                        RetroSnakeSpinnerView()
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if let plan = session.mealPlan, !plan.meals.isEmpty {
                        TabView {
                            ForEach(plan.meals) { meal in
                                mealCard(meal)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 28)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(maxHeight: .infinity)

                        Text(plan.sourceNote)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(steel)
                            .padding(.horizontal, 4)
                    } else {
                        Spacer()
                        Text("No meal plan yet.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)
                        Spacer()
                    }
                }
                .padding(20)
            }
            .navigationTitle("Meal plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        Task { await session.refreshMealPlan(force: true) }
                    }
                    .disabled(session.isMealPlanLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await session.ensureMealPlan()
            }
        }
        .preferredColorScheme(.light)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's ahead")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            if let plan = session.mealPlan {
                Text("Cap \(plan.maxKcal) kcal · protein \(plan.proteinGrams) g · \(plan.dietRaw)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            } else {
                Text("Grounded in your deficit, diet prefs, and fasting window.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            }
        }
    }

    private func mealCard(_ meal: MealPlanMeal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(meal.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Text(meal.timeLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
            }

            Text(meal.ingredients.joined(separator: " · "))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                labeled("Macro", meal.keyMacro)
                labeled("Micro", meal.keyMicro)
            }

            Text("~\(meal.approxKcal) kcal")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: ink.opacity(0.08), radius: 18, y: 8)
    }

    private func labeled(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
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
