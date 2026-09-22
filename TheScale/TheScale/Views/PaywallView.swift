import StoreKit
import SwiftUI

/// One-pager upgrade sheet. High contrast, clear Free / Plus / Pro hierarchy.
struct PaywallView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var store = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss

    var lockMessage: String?
    var highlighted: ScalePlan = .plus

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.32, green: 0.34, blue: 0.38)
    private let accent = Color(red: 0.10, green: 0.42, blue: 0.48)
    private let sheet = Color(red: 0.96, green: 0.97, blue: 0.98)

    var body: some View {
        NavigationStack {
            ZStack {
                sheet.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 18)

                    tierStack
                        .padding(.horizontal, 18)

                    Spacer(minLength: 12)

                    footer
                        .padding(.horizontal, 22)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("Unlock Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .task { await store.refresh() }
            .preferredColorScheme(.light)
        }
    }

    private var header: some View {
        let snap = store.quotaSnapshot
        return VStack(alignment: .leading, spacing: 10) {
            Text("Coach plans")
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundStyle(ink)

            Text("Weigh-in, Health, and charts stay free. Live Keel uses a weekly credit pool.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)

            if let lockMessage, !lockMessage.isEmpty {
                Text(lockMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.28, blue: 0.05))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.92, blue: 0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 10) {
                Text("\(snap.percentUsed)% used")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text("·")
                    .foregroundStyle(steel)
                Text("\(snap.used)/\(snap.limit) this week")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(steel)
                Spacer(minLength: 0)
                Text(store.plan.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            ProgressView(value: Double(snap.percentUsed), total: 100)
                .tint(snap.isExhausted ? Color.orange : accent)
        }
    }

    private var tierStack: some View {
        VStack(spacing: 10) {
            ForEach(ScalePlan.allCases) { plan in
                tierRow(plan)
            }
        }
    }

    private func tierRow(_ plan: ScalePlan) -> some View {
        let isCurrent = plan == store.plan
        let isHighlight = plan == highlighted && !isCurrent
        let isPro = plan == .pro

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                if isHighlight {
                    Text("Recommended")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                }
                Spacer(minLength: 8)
                Text(plan.priceLabel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
            }

            Text("\(plan.weeklyGrokCredits) live Keel credits / week")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            Text(shortBlurb(plan))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrent {
                Text("Your current plan")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.45, blue: 0.28))
            } else if plan != .free {
                Button {
                    Task {
                        let ok = await store.purchase(plan)
                        if ok { dismiss() }
                    }
                } label: {
                    Text(isHighlight ? "Upgrade to \(plan.displayName)" : "Choose \(plan.displayName)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    isHighlight || isPro ? accent : ink,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sheet, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isHighlight ? accent : ink.opacity(0.14),
                    lineWidth: isHighlight ? 2 : 1
                )
        )
    }

    private func shortBlurb(_ plan: ScalePlan) -> String {
        switch plan {
        case .free:
            return "Full scale + Health. 5 Keel asks to try Coach."
        case .plus:
            return "Daily Coach. About 4 live asks per day."
        case .pro:
            return "Heavy Coach weeks. Room for power days."
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let err = store.purchaseError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.7, green: 0.12, blue: 0.12))
                    .multilineTextAlignment(.center)
            }
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(steel)
            Text("Cancel anytime in App Store subscriptions.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(steel.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PaywallView(lockMessage: "Weekly limit hit on Free (5/5).", highlighted: .plus)
        .environmentObject(ScaleSessionViewModel())
}
