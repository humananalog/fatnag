import SwiftUI

/// Home gauge composition: **Vector Crosshair**.
/// One HUD-style crosshair with weekly % at the reticule and four cardinal arc gauges
/// (steps / energy / protein / micro). Not Apple Activity rings.
struct VectorCrosshairGaugesView: View {
    var weeklyPercent: Int
    var bandLabel: String
    var metrics: [DailyMetricProgress]
    var ink: Color
    var steel: Color
    var accent: Color

    private let gaugeSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Outer lattice diamond
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 1)
                    .frame(width: 210, height: 210)
                    .rotationEffect(.degrees(45))

                // Cardinal gauges
                gauge(for: .steps)
                    .offset(y: -88)
                gauge(for: .energy)
                    .offset(x: 88)
                gauge(for: .protein)
                    .offset(y: 88)
                gauge(for: .micro)
                    .offset(x: -88)

                // Center reticule: weekly completion
                ZStack {
                    Circle()
                        .strokeBorder(ink.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 96, height: 96)
                    Circle()
                        .strokeBorder(accent.opacity(0.55), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    // Crosshair ticks
                    Capsule().fill(ink.opacity(0.35)).frame(width: 1.5, height: 14).offset(y: -40)
                    Capsule().fill(ink.opacity(0.35)).frame(width: 1.5, height: 14).offset(y: 40)
                    Capsule().fill(ink.opacity(0.35)).frame(width: 14, height: 1.5).offset(x: -40)
                    Capsule().fill(ink.opacity(0.35)).frame(width: 14, height: 1.5).offset(x: 40)

                    VStack(spacing: 2) {
                        Text("\(weeklyPercent)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                        Text("%")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(steel)
                        Text(bandLabel.uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Week goal \(weeklyPercent) percent, \(bandLabel)")
                .accessibilityIdentifier("home.crosshair.week")
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("home.vectorCrosshair")
        }
    }

    @ViewBuilder
    private func gauge(for kind: DailyMetricProgress.Kind) -> some View {
        let row = metrics.first(where: { $0.kind == kind })
        let fraction = min(max(row?.fraction ?? 0, 0), 1.15)
        let color = statusColor(row?.status ?? .unknown)

        VStack(spacing: 3) {
            ZStack {
                // Arc track (270 deg open ring; not a closed Activity ring)
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(ink.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                Circle()
                    .trim(from: 0.12, to: 0.12 + 0.76 * min(fraction, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                // Needle pip at progress tip
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(y: -gaugeSize / 2 + 2.5)
                    .rotationEffect(.degrees(-180 + 270 * min(fraction, 1)))

                Text(shortTitle(kind))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(ink.opacity(0.7))
            }
            .frame(width: gaugeSize, height: gaugeSize)

            Text(statusChip(row))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row?.accessibilitySummary ?? "\(kind.rawValue) unavailable")
        .accessibilityIdentifier("home.todayMetrics.\(kind.rawValue)")
    }

    private func shortTitle(_ kind: DailyMetricProgress.Kind) -> String {
        switch kind {
        case .steps: return "STEPS"
        case .energy: return "ENERGY"
        case .protein: return "PROTEIN"
        case .micro: return "MICRO"
        }
    }

    private func statusChip(_ row: DailyMetricProgress?) -> String {
        guard let row else { return "-" }
        switch row.status {
        case .complete: return "DONE"
        case .over: return "OVER"
        case .unknown: return "OPEN"
        case .inProgress:
            return "\(Int((min(row.fraction, 1) * 100).rounded()))%"
        }
    }

    private func statusColor(_ status: DailyMetricProgress.Status) -> Color {
        switch status {
        case .complete: return Color(red: 0.12, green: 0.42, blue: 0.30)
        case .over: return Color(red: 0.72, green: 0.22, blue: 0.18)
        case .inProgress: return accent
        case .unknown: return ink.opacity(0.28)
        }
    }
}
