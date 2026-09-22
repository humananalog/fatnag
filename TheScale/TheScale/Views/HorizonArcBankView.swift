import SwiftUI

/// Home day board: large weekly hero, activity gauges (steps / move), and
/// daily nutrition **targets** unless Apple Health has a robust food log.
struct HorizonArcBankView: View {
    var weeklyPercent: Int
    var bandLabel: String
    var weekTitle: String
    var metrics: [DailyMetricProgress]
    var targetChips: [HomeDailyTargetChip]
    var ink: Color
    var steel: Color
    var accent: Color
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            weeklyHero
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

    private var weeklyHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(weeklyPercent)")
                    .font(.system(size: compact ? 56 : 68, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("home.weekPercent")

                VStack(alignment: .leading, spacing: 3) {
                    Text(bandLabel.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(ink)
                    Text("% of week")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(steel)
                }
                Spacer(minLength: 0)
            }

            Text(weekTitle)
                .font(.system(size: compact ? 15 : 17, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week goal \(weeklyPercent) percent, \(bandLabel). \(weekTitle)")
        .accessibilityIdentifier("home.weekHero")
    }

    private var activityGauges: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(ink.opacity(0.55))

            HStack(alignment: .top, spacing: 14) {
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
            HStack(alignment: .firstTextBaseline) {
                Text(row.title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(ink.opacity(0.7))
                Spacer(minLength: 4)
                Text(statusChip(row))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            ZStack {
                HorizonArcTrack()
                    .stroke(ink.opacity(0.14), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                HorizonArcTrack()
                    .trim(from: 0, to: min(CGFloat(fraction), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
            .frame(height: compact ? 40 : 48)
            .frame(maxWidth: .infinity)

            Text(row.currentLine)
                .font(.system(size: compact ? 18 : 20, weight: .bold, design: .rounded))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("DAILY TARGETS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(ink.opacity(0.55))
                .accessibilityIdentifier("home.dailyTargets.title")

            HStack(alignment: .top, spacing: 10) {
                ForEach(targetChips) { chip in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chip.title.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(ink.opacity(0.55))
                        Text(chip.valueLine)
                            .font(.system(size: compact ? 15 : 16, weight: .bold, design: .rounded))
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

    private func statusChip(_ row: DailyMetricProgress) -> String {
        switch row.status {
        case .complete: return "Done"
        case .over: return "Over"
        case .unknown: return "Open"
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
