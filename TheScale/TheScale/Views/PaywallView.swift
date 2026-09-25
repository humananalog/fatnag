import StoreKit
import SwiftUI

private struct PaywallScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Luxury paywall sheet. Hero kisses the top edge; Close floats over it. Width-safe.
struct PaywallView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var store = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss

    var lockMessage: String?
    /// Soft nudge for the next step up. Pro stays visually primary either way.
    var highlighted: ScalePlan = .pro

    @State private var scrollY: CGFloat = 0
    @State private var appeared = false

    private var universe: ScalePaletteUniverse {
        .resolve(sex: session.profile.sex)
    }

    private var ink: Color { universe.paywallInk }
    private let ivory = Color(red: 0.96, green: 0.95, blue: 0.92)
    private let mist = Color(red: 0.72, green: 0.70, blue: 0.66)
    private var gold: Color { universe.paywallGold }
    private var goldDeep: Color { universe.paywallGoldDeep }

    /// Room under the sheet drag gripper before chrome controls.
    private let gripperClearance: CGFloat = 18

    private var heroName: String {
        session.profile.sex == .female ? "PaywallHeroFemale" : "PaywallHeroMale"
    }

    private var heroDim: Double {
        let progress = min(max(Double(-scrollY) / 220.0, 0), 1)
        return 0.12 + progress * 0.58
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let heroHeight = min(max(geo.size.height * 0.50, 300), 460)

            ZStack(alignment: .top) {
                ink.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroBlock(width: width, height: heroHeight)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: PaywallScrollOffsetKey.self,
                                        value: proxy.frame(in: .named("paywallScroll")).minY
                                    )
                                }
                            )

                        panelContent
                            .frame(width: width)
                            .background(ink)
                    }
                }
                .coordinateSpace(name: "paywallScroll")
                .onPreferenceChange(PaywallScrollOffsetKey.self) { scrollY = $0 }
                .ignoresSafeArea(edges: .top)

                // Close overlays the hero; sits below the system gripper.
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ivory)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(ivory.opacity(0.22), lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                    .padding(.trailing, 16)
                    .padding(.top, gripperClearance)
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .zIndex(2)
            }
            .frame(width: width, height: geo.size.height)
            .clipped()
        }
        .background(ink.ignoresSafeArea())
        .task { await store.refresh() }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }

    // MARK: - Hero

    private func heroBlock(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(heroName)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .accessibilityHidden(true)

            // Soft top wash so gripper + Close stay readable
            LinearGradient(
                colors: [ink.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            .allowsHitTesting(false)

            // Bottom dissolve into the panel
            LinearGradient(
                colors: [
                    .clear,
                    ink.opacity(0.28),
                    ink.opacity(0.86),
                    ink
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height * 0.55)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            ink.opacity(heroDim)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                Text("THE SCALE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(gold.opacity(0.95))

                Text("Stay sharp.")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .foregroundStyle(ivory)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)

                Text("Credits do not buy pleasure. Credits buy better outcomes.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(gold.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.creditsLine")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    // MARK: - Panel

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Keel when you go soft. Pro is the pressure path.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            if let lockMessage, !lockMessage.isEmpty {
                lockChip(lockMessage)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            #if DEBUG
            Text("DEV: tap any tier to apply instantly. StoreKit bypassed until Settings → Use StoreKit.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(gold.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .accessibilityIdentifier("paywall.devTierHint")
            #endif

            usageStrip
                .padding(.horizontal, 24)
                .padding(.top, 18)

            if store.isLoading && store.products.isEmpty {
                catalogLoading
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            } else if store.hasEmptyCatalog && !store.allowsInstantDevTier {
                catalogEmpty
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            }

            tierStack
                .padding(.horizontal, 20)
                .padding(.top, 20)

            footer
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0.4)
    }

    private var catalogLoading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(mist)
            Text("Loading App Store prices…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mist)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ivory.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("paywall.catalogLoading")
    }

    private var catalogEmpty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions unavailable")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(ivory)
            Text(
                store.purchaseError
                    ?? "Plus and Pro aren’t in the App Store catalog yet. Try Restore, or check back after products go live under Human Analog."
            )
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(mist)
            .fixedSize(horizontal: false, vertical: true)
            Button("Retry") {
                Task { await store.refresh() }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(gold)
            .disabled(store.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ivory.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.45, blue: 0.42).opacity(0.35), lineWidth: 1)
        )
        .accessibilityIdentifier("paywall.catalogEmpty")
    }

    private func lockChip(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.95, green: 0.84, blue: 0.58))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [goldDeep.opacity(0.42), goldDeep.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(gold.opacity(0.40), lineWidth: 1)
            )
    }

    private var usageStrip: some View {
        let snap = store.quotaSnapshot
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(snap.used)/\(snap.limit) this week")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ivory.opacity(0.92))
                Text("·")
                    .foregroundStyle(mist.opacity(0.65))
                Text(store.plan.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(gold)
                Spacer(minLength: 0)
            }
            ScaleBoundedProgress(
                value: Double(snap.percentUsed),
                total: 100,
                tint: snap.isExhausted ? Color.orange : gold,
                track: ivory.opacity(0.14),
                height: 7
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ivory.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ivory.opacity(0.08), lineWidth: 1)
        )
    }

    private var tierStack: some View {
        VStack(spacing: 12) {
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                Text(store.priceLabel(for: plan))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPro ? gold : mist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text("\(plan.weeklyGrokCredits)/wk · \(plan.paywallArgument)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrent {
                Text(store.allowsInstantDevTier ? "Current · tap another tier to switch" : "Current plan")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 0.62))
            }

            if store.allowsInstantDevTier {
                Button {
                    #if DEBUG
                    _ = store.applyDevPlan(plan)
                    dismiss()
                    #endif
                } label: {
                    Text(isCurrent ? "Keep \(plan.displayName)" : "Use \(plan.displayName)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isPro ? 14 : 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPro && !isCurrent ? ink : ivory)
                .background {
                    if isPro && !isCurrent {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [gold, gold.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ivory.opacity(isCurrent ? 0.08 : 0.12))
                    }
                }
                .accessibilityIdentifier("paywall.devSelect.\(plan.rawValue)")
            } else if !isCurrent, plan != .free {
                Button {
                    Task {
                        let ok = await store.purchase(plan)
                        if ok { dismiss() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isPurchasing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(isPro ? ink : ivory)
                        }
                        Text(isPro ? "Go Pro" : "Choose \(plan.displayName)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isPro ? 14 : 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPro ? ink : ivory)
                .disabled(store.isBusy || store.product(for: plan) == nil)
                .opacity(store.product(for: plan) == nil ? 0.45 : 1)
                .background {
                    if isPro {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [gold, gold.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ivory.opacity(0.12))
                    }
                }
                .accessibilityIdentifier("paywall.buy.\(plan.rawValue)")
            }
        }
        .padding(isPro ? 18 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isPro ? gold.opacity(0.12) : ivory.opacity(0.045))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isPro ? gold.opacity(0.88) : ivory.opacity(0.12),
                    lineWidth: isPro ? 1.5 : 1
                )
        )
        .shadow(color: isPro ? gold.opacity(0.18) : .clear, radius: 18, y: 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let err = store.purchaseError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.purchaseError")
            }
            if let restore = store.restoreMessage {
                Text(restore)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.restoreMessage")
            }
            Button {
                Task { await store.restore() }
            } label: {
                HStack(spacing: 8) {
                    if store.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                            .tint(mist)
                    }
                    Text(store.isRestoring ? "Restoring…" : "Restore purchases")
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(mist)
            .disabled(store.isBusy)
            .accessibilityIdentifier("paywall.restore")
            Text("Cancel anytime in App Store subscriptions. Privacy Policy and Terms are in Settings.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(mist.opacity(0.75))
                .multilineTextAlignment(.center)
            #if DEBUG
            if store.isDevPlanOverrideActive {
                Text("Active via DEV override · \(store.plan.displayName)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(gold.opacity(0.75))
                    .accessibilityIdentifier("paywall.devOverrideActive")
            }
            #endif
            Text(store.commerceLane.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(mist.opacity(0.55))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("paywall.commerceLane")
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
