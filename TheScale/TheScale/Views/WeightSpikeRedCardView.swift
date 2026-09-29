import SwiftUI

/// Full-screen reality-check after a confirmed short-term weight spike.
struct WeightSpikeRedCardView: View {
    let plan: WeightRecoveryPlan
    let onDismiss: () -> Void

    private let ink = Color.white
    private let blood = Color(red: 0.72, green: 0.12, blue: 0.14)
    private let void = Color(red: 0.06, green: 0.05, blue: 0.06)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [blood, void],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text(AppLanguageStore.text("spike.red.badge", default: "RED CARD"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(ink.opacity(0.75))

                Text(plan.kickHeadline)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(plan.kickBody)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plan.actionLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ink.opacity(0.85))
                            Text(line)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8)

                Text(plan.pacingLine)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.7))
                    .padding(.top, 4)

                Spacer(minLength: 12)

                Button(action: onDismiss) {
                    Text(AppLanguageStore.text("spike.red.cta", default: "Got it. Back on track."))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .foregroundStyle(blood)
                .accessibilityIdentifier("spike.red.dismiss")
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }
}
