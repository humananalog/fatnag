import SwiftUI

/// Full-screen Monday morning hero: motivation + insight + Sunday kg target.
/// One composition (not a dashboard). Wires AggressiveWeeklyTargetEngine mode + difficulty tier.
struct MondayWeeklyCardView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var appeared = false
    @State private var showDetail = false

    private let void = Color(red: 0.04, green: 0.05, blue: 0.07)
    private let deep = Color(red: 0.07, green: 0.10, blue: 0.14)
    private let ivory = Color(red: 0.96, green: 0.95, blue: 0.92)
    private let mist = Color(red: 0.62, green: 0.64, blue: 0.68)
    private let gold = Color(red: 0.82, green: 0.66, blue: 0.40)

    private var mode: WeeklyTargetMode {
        session.mondayCard?.sundayGoal.mode ?? session.weeklyTargetMode
    }

    private var accent: Color {
        switch mode {
        case .hardcoreCatchUp: return Color(red: 0.86, green: 0.32, blue: 0.24)
        case .accelerate: return Color(red: 0.72, green: 0.92, blue: 0.28)
        case .aggressive: return Color(red: 0.35, green: 0.78, blue: 0.92)
        case .hold: return gold
        }
    }

    private var difficultyTitle: String? {
        let raw = session.profile.goalDifficultyTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private var weekTitle: String {
        if let difficultyTitle {
            return "\(mode.mondayHeroBadge) · \(difficultyTitle)"
        }
        return mode.mondayHeroBadge
    }

    var body: some View {
        ZStack {
            atmosphere.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if let card = session.mondayCard {
                    heroContent(card)
                } else {
                    loadingBlock
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityIdentifier("mondayHero")
    }

    private var atmosphere: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slow = t / 16.0
            ZStack {
                LinearGradient(
                    colors: [deep, void, Color(red: 0.05, green: 0.08, blue: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Ellipse()
                    .fill(accent.opacity(0.28))
                    .frame(width: 340, height: 280)
                    .blur(radius: 56)
                    .offset(x: -70 + CGFloat(sin(slow)) * 36, y: -150 + CGFloat(cos(slow * 0.7)) * 28)
                Ellipse()
                    .fill(Color(red: 0.18, green: 0.42, blue: 0.48).opacity(0.18))
                    .frame(width: 380, height: 300)
                    .blur(radius: 64)
                    .offset(x: 90 + CGFloat(cos(slow * 0.55)) * 32, y: 140 + CGFloat(sin(slow * 0.9)) * 24)
                RadialGradient(
                    colors: [accent.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 420
                )
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                session.dismissMondayCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ivory.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(String(localized: "monday.close_a11y", defaultValue: "Close Monday card"))

            Spacer(minLength: 8)

            if session.isMondayCardLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(ivory)
            }
        }
        .padding(.bottom, 8)
    }

    private var loadingBlock: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(ivory)
            Text(String(localized: "monday.building", defaultValue: "Building this week's card…"))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroContent(_ card: MondayCardPayload) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)

            Text(weekTitle)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(accent)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .accessibilityIdentifier("mondayHero.badge")

            Text(String(localized: "monday.this_week", defaultValue: "This week"))
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ivory.opacity(0.72))
                .padding(.top, 14)
                .opacity(appeared ? 1 : 0)

            Text(String(format: "%.1f", UnitFormat.mass(fromKg: card.sundayGoal.targetKg, system: session.preferredUnits)))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ivory)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .accessibilityIdentifier("mondayHero.sundayKg")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(session.preferredUnits.massLabel) Sunday")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(mist)
                Text(card.sundayGoal.sundayDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ivory.opacity(0.78))
            }
            .padding(.top, 2)

            Text("\(UnitFormat.massDeltaString(card.sundayGoal.weeklyDeltaKg, system: session.preferredUnits)) this week")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent.opacity(0.95))
                .padding(.top, 8)

            Text(displayEncouragement(card))
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(ivory)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .padding(.top, 28)
                .opacity(appeared ? 1 : 0)
                .accessibilityIdentifier("mondayHero.insight")

            if showDetail {
                detailBlock(card)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 16)

            Button {
                session.dismissMondayCard()
            } label: {
                Text(mode.mondayHeroCTA)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(void)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)
            .accessibilityIdentifier("mondayHero.cta")

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    showDetail.toggle()
                }
            } label: {
                Text(showDetail
                      ? String(localized: "monday.hide_detail", defaultValue: "Hide detail")
                      : String(localized: "monday.meals_physics", defaultValue: "Meals & physics"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(mist)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mondayHero.detailToggle")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailBlock(_ card: MondayCardPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(displayMeals(card))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(ivory.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(5)
                .minimumScaleFactor(0.85)

            Text(displayDiagnostic(card))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(8)
                .minimumScaleFactor(0.85)
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
        .environmentObject({
            let s = ScaleSessionViewModel()
            return s
        }())
}
