import StoreKit
import SwiftUI

private struct PaywallScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Luxury one-pager. Hero is a static background; content scrolls over it and fades as you go down.
struct PaywallView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var store = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss

    var lockMessage: String?
    /// Soft nudge for the next step up. Pro stays visually primary either way.
    var highlighted: ScalePlan = .pro

    @State private var scrollY: CGFloat = 0

    private let ink = Color(red: 0.06, green: 0.07, blue: 0.09)
    private let ivory = Color(red: 0.96, green: 0.95, blue: 0.92)
    private let mist = Color(red: 0.72, green: 0.70, blue: 0.66)
    private let gold = Color(red: 0.78, green: 0.62, blue: 0.38)
    private let goldDeep = Color(red: 0.55, green: 0.42, blue: 0.22)
    private let heroHeight: CGFloat = 420

    private var heroName: String {
        session.profile.sex == .female ? "PaywallHeroFemale" : "PaywallHeroMale"
    }

    /// 1 at top → fades toward 0 as content scrolls down over the hero.
    private var contentFade: Double {
        let progress = min(max(Double(-scrollY) / 280.0, 0), 1)
        return max(0.28, 1.0 - progress * 0.72)
    }

    private var heroScrim: Double {
        let progress = min(max(Double(-scrollY) / 220.0, 0), 1)
        return 0.35 + progress * 0.55
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // STATIC hero background (does not scroll)
                Image(heroName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                ink.opacity(heroScrim)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: heroHeight * 0.55)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: PaywallScrollOffsetKey.self,
                                        value: geo.frame(in: .named("paywallScroll")).minY
                                    )
                                }
                            )

                        VStack(spacing: 0) {
                            copyBlock
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                            if let lockMessage, !lockMessage.isEmpty {
                                lockChip(lockMessage)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 14)
                            }
                            usageStrip
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                            tierStack
                                .padding(.horizontal, 20)
                                .padding(.top, 18)
                            footer
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                                .padding(.bottom, 36)
                        }
                        .padding(.top, 20)
                        .background(
                            LinearGradient(
                                colors: [
                                    ink.opacity(0.15),
                                    ink.opacity(0.92),
                                    ink
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(contentFade)
                    }
                }
                .coordinateSpace(name: "paywallScroll")
                .onPreferenceChange(PaywallScrollOffsetKey.self) { scrollY = $0 }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(ivory.opacity(0.9))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await store.refresh() }
            .preferredColorScheme(.dark)
        }
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stay sharp.")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(ivory)

            Text("Credits do not buy pleasure. Credits buy better outcomes.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(gold.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.creditsLine")

            Text("Live Keel when you go soft. Pro is the pressure path.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lockChip(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(goldDeep.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(gold.opacity(0.35), lineWidth: 1)
            )
    }

    private var usageStrip: some View {
        let snap = store.quotaSnapshot
        return HStack(spacing: 8) {
            Text("\(snap.used)/\(snap.limit) this week")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ivory.opacity(0.9))
            Text("·")
                .foregroundStyle(mist.opacity(0.7))
            Text(store.plan.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(gold)
            Spacer(minLength: 0)
            ProgressView(value: Double(snap.percentUsed), total: 100)
                .tint(snap.isExhausted ? Color.orange : gold)
                .frame(width: 72)
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
        let isPro = plan == .pro
        let isStep = plan == highlighted && !isCurrent && !isPro

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plan.displayName)
                    .font(.system(size: isPro ? 22 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ivory)
                if isPro && !isCurrent {
                    Text("Best")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(gold, in: Capsule())
                } else if isStep {
                    Text("Next")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ivory.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ivory.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(plan.priceLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPro ? gold : mist)
            }

            Text("\(plan.weeklyGrokCredits)/wk · \(plan.paywallArgument)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrent {
                Text("Current plan")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 0.62))
            } else if plan != .free {
                Button {
                    Task {
                        let ok = await store.purchase(plan)
                        if ok { dismiss() }
                    }
                } label: {
                    Text(isPro ? "Go Pro" : "Choose \(plan.displayName)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isPro ? 14 : 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPro ? ink : ivory)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPro ? gold : ivory.opacity(0.12))
                }
            }
        }
        .padding(isPro ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isPro ? gold.opacity(0.10) : ivory.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isPro ? gold.opacity(0.85) : ivory.opacity(0.12),
                    lineWidth: isPro ? 1.5 : 1
                )
        )
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let err = store.purchaseError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                    .multilineTextAlignment(.center)
            }
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(mist)
            Text("Cancel anytime in App Store subscriptions.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(mist.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Male") {
    PaywallView(lockMessage: "Weekly limit hit on Free (5/5).", highlighted: .plus)
        .environmentObject({
            let s = ScaleSessionViewModel()
            s.profile.sex = .male
            return s
        }())
}

#Preview("Female") {
    PaywallView(highlighted: .pro)
        .environmentObject({
            let s = ScaleSessionViewModel()
            s.profile.sex = .female
            return s
        }())
}
