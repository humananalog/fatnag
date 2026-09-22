import SwiftUI

/// One-screen Monday morning post-weigh card: progress, Sunday goal, meals, Keel diagnostic.
struct MondayWeeklyCardView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let accent = Color(red: 0.12, green: 0.45, blue: 0.48)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let card = session.mondayCard {
                content(card)
            } else {
                loadingBlock
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 0.98),
                    Color(red: 0.88, green: 0.91, blue: 0.93),
                    Color(red: 0.82, green: 0.86, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack {
            Button {
                session.dismissMondayCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close Monday card")

            VStack(alignment: .leading, spacing: 2) {
                Text("Monday")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text("Week plan after weigh-in")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
            }
            Spacer(minLength: 8)
            if session.isMondayCardLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.bottom, 10)
    }

    private var loadingBlock: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Building this week's card…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ card: MondayCardPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            progressBlock(card.progress, currentKg: card.currentKg)
            sundayBlock(card.sundayGoal)
            Text(displayEncouragement(card))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .minimumScaleFactor(0.85)

            mealsBlock(displayMeals(card))
            diagnosticBlock(displayDiagnostic(card))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func progressBlock(_ progress: MondayWeekProgress, currentKg: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last week")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.1f", currentKg))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                Text("kg")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
                Spacer(minLength: 8)
                if let delta = progress.weightDeltaKg {
                    Text(String(format: "%+.2f", delta))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
            }
            Text(progress.summaryLine)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(progress.adherenceLine)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(steel.opacity(0.85))
                .lineLimit(2)
            Text(progress.signalLines.joined(separator: " · "))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(steel.opacity(0.75))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private func sundayBlock(_ goal: MondaySundayGoal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sunday goal")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", goal.targetKg))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("kg")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
                Spacer(minLength: 6)
                Text(goal.sundayDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(goal.pacingLine)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func mealsBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meals")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.88))
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func diagnosticBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Instructor")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
                .textCase(.uppercase)
            ScrollView {
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 140)
        }
    }

    private func displayEncouragement(_ card: MondayCardPayload) -> String {
        let live = session.mondayCardStreamEncouragement
        if !live.isEmpty { return live }
        return card.encouragement.isEmpty ? "…" : card.encouragement
    }

    private func displayMeals(_ card: MondayCardPayload) -> String {
        let live = session.mondayCardStreamMeals
        if !live.isEmpty { return live }
        return card.meals.isEmpty ? "…" : card.meals
    }

    private func displayDiagnostic(_ card: MondayCardPayload) -> String {
        let live = session.mondayCardStreamDiagnostic
        if !live.isEmpty { return live }
        return card.diagnostic.isEmpty ? "…" : card.diagnostic
    }
}

#Preview {
    MondayWeeklyCardView()
        .environmentObject(ScaleSessionViewModel())
}
