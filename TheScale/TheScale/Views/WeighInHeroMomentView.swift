import SwiftUI

/// Full-screen post-weigh hero moment: sergeant / encourage / skeptical with punchy copy.
struct WeighInHeroMomentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var appeared = false

    private var card: WeighInAnalysisCard? { session.lastWeighInAnalysis }

    private var ink: Color { Color(red: 0.05, green: 0.06, blue: 0.08) }
    private var ivory: Color { Color(red: 0.96, green: 0.95, blue: 0.92) }

    private var accent: Color {
        switch card?.tone {
        case .sergeant: return Color(red: 0.86, green: 0.32, blue: 0.24)
        case .encourage: return Color(red: 0.28, green: 0.72, blue: 0.48)
        case .skeptical: return Color(red: 0.82, green: 0.66, blue: 0.40)
        case .none: return Color(red: 0.82, green: 0.66, blue: 0.40)
        }
    }

    var body: some View {
        ZStack {
            atmosphere.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                if let card {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(card.tone.badge(sex: card.sex))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(2.0)
                            .foregroundStyle(accent)

                        Text(card.headline)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(ivory)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("weighInHero.headline")

                        Text(card.body)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(ivory.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        if !card.popLine.isEmpty {
                            Text(card.popLine)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(accent.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                                .accessibilityIdentifier("weighInHero.popLine")
                        }

                        if let deltaText = card.deltaDisplay(system: session.preferredUnits) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(deltaText)
                                    .font(.system(size: card.isWinnerLoss ? 44 : 22, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(card.isWinnerLoss ? accent : ivory.opacity(0.85))
                                    .accessibilityIdentifier("weighInHero.delta")
                                if card.isWinnerLoss {
                                    Text(String(localized: "home.winner", defaultValue: "You're a winner."))
                                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                                        .foregroundStyle(ivory)
                                        .accessibilityIdentifier("weighInHero.winner")
                                }
                                Text("\(UnitFormat.massString(card.weighedKg, system: session.preferredUnits, fractionDigits: 1)) now")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(ivory.opacity(0.7))
                            }
                            .padding(.top, 8)
                        } else {
                            Text("\(UnitFormat.massString(card.weighedKg, system: session.preferredUnits, fractionDigits: 1)) locked")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ivory.opacity(0.7))
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 28)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                }

                Spacer(minLength: 24)

                Button {
                    session.dismissWeighInHero()
                } label: {
                    Text(card.map { $0.tone.cta(sex: $0.sex) }
                          ?? String(localized: "common.continue", defaultValue: "Continue"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .opacity(appeared ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityIdentifier("weighInHero")
    }

    private var atmosphere: some View {
        ZStack {
            ink
            RadialGradient(
                colors: [accent.opacity(0.38), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [accent.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
    }
}

#if DEBUG
#Preview("Sergeant") {
    WeighInHeroMomentView()
        .environmentObject({
            let s = ScaleSessionViewModel()
            s.previewInjectWeighInHero(
                WeighInAnalysisCard(
                    tone: .sergeant,
                    headline: "Drop and give me zero snacks, Alex.",
                    body: "+0.40 kg since last. Fix dinner tonight.",
                    deltaKg: 0.4,
                    weighedKg: 93.7,
                    createdAt: Date(),
                    popLine: "Rocky didn't hit the fridge after round twelve.",
                    sex: .male
                )
            )
            return s
        }())
}
#endif
