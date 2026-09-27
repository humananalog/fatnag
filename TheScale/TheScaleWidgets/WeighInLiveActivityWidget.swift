import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TheScaleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WeighInLiveActivityWidget()
    }
}

struct WeighInLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WeighInActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.scaleName, systemImage: "scalemass.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isSettled ? "Settled" : "Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isSettled ? .green : .orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let kg = context.state.weightKg {
                        Text(String(format: "%.2f kg", kg))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("-")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "scalemass.fill")
            } compactTrailing: {
                if let kg = context.state.weightKg {
                    Text(String(format: "%.1f", kg))
                        .monospacedDigit()
                        .font(.caption.weight(.bold))
                } else {
                    Image(systemName: "ellipsis")
                }
            } minimal: {
                Image(systemName: "scalemass.fill")
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WeighInActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "scalemass.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("FATNAG · \(context.attributes.scaleName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let kg = context.state.weightKg {
                    Text(String(format: "%.2f kg", kg))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(context.state.statusLine)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                Text(context.state.statusLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }
}
