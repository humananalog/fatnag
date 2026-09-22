import StoreKit
import SwiftUI

/// Upgrade sheet when weekly Grok credits are exhausted (or from Settings).
struct PaywallView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @ObservedObject private var store = ScaleSubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss

    var lockMessage: String?
    var highlighted: ScalePlan = .plus

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Coach plans")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("Full weigh-in, Health, charts, and on-device Coach on every plan. Live Grok is weekly-limited so token costs stay honest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let lockMessage, !lockMessage.isEmpty {
                        Text(lockMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    let snap = store.quotaSnapshot
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snap.statusLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(snap.usageCountLine + " · " + snap.percentLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(snap.percentUsed), total: 100)
                            .tint(snap.isExhausted ? .orange : Color(red: 0.18, green: 0.52, blue: 0.62))
                    }

                    ForEach(ScalePlan.allCases) { plan in
                        planCard(plan, current: store.plan, highlight: highlighted)
                    }

                    if let err = store.purchaseError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Button("Restore purchases") {
                        Task { await store.restore() }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.96, blue: 0.98),
                        Color(red: 0.88, green: 0.91, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Unlock Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await store.refresh() }
        }
    }

    private func planCard(_ plan: ScalePlan, current: ScalePlan, highlight: ScalePlan) -> some View {
        let isCurrent = plan == current
        let isHighlight = plan == highlight && !isCurrent
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.displayName)
                    .font(.headline)
                Spacer()
                Text(plan.priceLabel)
                    .font(.subheadline.weight(.semibold))
            }
            Text(plan.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(plan.weeklyGrokCredits) Grok credits / week")
                .font(.caption2.weight(.semibold))

            if isCurrent {
                Text("Current plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if plan != .free {
                Button {
                    Task {
                        let ok = await store.purchase(plan)
                        if ok { dismiss() }
                    }
                } label: {
                    Text(isHighlight ? "Unlock \(plan.displayName)" : "Choose \(plan.displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isHighlight ? Color(red: 0.12, green: 0.35, blue: 0.28) : .primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isHighlight ? Color(red: 0.12, green: 0.35, blue: 0.28).opacity(0.10) : Color.white.opacity(0.72)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHighlight ? Color(red: 0.12, green: 0.35, blue: 0.28).opacity(0.45) : .clear, lineWidth: 1.5)
        )
    }
}

#Preview {
    PaywallView(lockMessage: "Weekly limit hit on Free (5/5).", highlighted: .plus)
        .environmentObject(ScaleSessionViewModel())
}
