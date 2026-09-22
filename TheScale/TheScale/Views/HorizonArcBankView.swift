import SwiftUI

/// Home day board: large Sunday weight target, lean activity gauges, and
/// daily nutrition **targets** unless Apple Health has a robust food log.
struct HorizonArcBankView: View {
    var sundayTargetKg: Double?
    var weeklyDeltaKg: Double
    var bandLabel: String
    var weekTitle: String
    var metrics: [DailyMetricProgress]
    var targetChips: [HomeDailyTargetChip]
    var ink: Color
    var steel: Color
    var accent: Color
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 22) {
            sundayHero
            if !metrics.isEmpty {
                activityGauges
            }
            if !targetChips.isEmpty {
                dailyTargets
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.horizonArcBank")
    }

    private var sundayHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUNDAY TARGET")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(ink.opacity(0.55))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let kg = sundayTargetKg {
                    Text(String(format: "%.2f", kg))
                        .font(.system(size: compact ? 64 : 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityIdentifier("home.sundayTargetKg")
                    Text("kg")
                        .font(.system(size: compact ? 24 : 28, weight: .bold, design: .rounded))
                        .foregroundStyle(steel)
                } else {
                    Text(weekTitle.isEmpty ? "Set goal" : weekTitle)
                        .font(.system(size: compact ? 36 : 44, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .accessibilityIdentifier("home.sundayTargetKg")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text(bandLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text(deltaChip)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(steel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sundayAccessibilityLabel)
        .accessibilityIdentifier("home.weekHero")
    }

    private var deltaChip: String {
        let sign = weeklyDeltaKg >= 0 ? "+" : ""
        return String(format: "%@%.2f kg this week", sign, weeklyDeltaKg)
    }

    private var sundayAccessibilityLabel: String {
        if let kg = sundayTargetKg {
            return String(format: "Sunday target %.2f kilograms. %@ . %@", kg, bandLabel, deltaChip)
        }
        return "\(weekTitle). \(bandLabel). \(deltaChip)"
    }

    private var activityGauges: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(ink.opacity(0.55))

            HStack(alignment: .top, spacing: 16) {
                ForEach(metrics, id: \.kind) { row in
                    gaugeCard(row)
                }
            }
        }
        .accessibilityIdentifier("home.todayMetrics")
    }

    private func gaugeCard(_ row: DailyMetricProgress) -> some View {
        let fraction = min(max(row.fraction, 0), 1.15)
        let color = statusColor(row.status)

        return VStack(alignment: .leading, spacing: 8) {
            Text(row.title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(ink.opacity(0.7))

            ZStack {
                HorizonArcTrack()
                    .stroke(ink.opacity(0.14), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                HorizonArcTrack()
                    .trim(from: 0, to: min(CGFloat(fraction), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
            .frame(height: compact ? 44 : 52)
            .frame(maxWidth: .infinity)

            Text(row.currentLine)
                .font(.system(size: compact ? 17 : 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary)
        .accessibilityIdentifier("home.todayMetrics.\(row.kind.rawValue)")
    }

    private var dailyTargets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY TARGETS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(ink.opacity(0.55))
                .accessibilityIdentifier("home.dailyTargets.title")

            HStack(alignment: .top, spacing: 12) {
                ForEach(targetChips) { chip in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chip.title.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(ink.opacity(0.55))
                        Text(chip.valueLine)
                            .font(.system(size: compact ? 15 : 17, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(chip.title) \(chip.valueLine)")
                }
            }
            .accessibilityIdentifier("home.dailyTargets")
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

private struct HorizonArcTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 4
        let start = CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        let end = CGPoint(x: rect.maxX - inset, y: rect.minY + inset * 0.4)
        let control = CGPoint(x: rect.midX * 0.55, y: rect.minY - rect.height * 0.15)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
